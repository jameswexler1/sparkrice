#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys


DEFAULT_GRAPH_IMAGE = "/tmp/cheater_graph.png"


class GraphRenderError(Exception):
    pass


def extract_json(raw: str):
    text = raw.strip()
    if not text:
        raise GraphRenderError("empty graph response")

    fence = re.search(r"```(?:json)?\s*(.*?)\s*```", text, re.IGNORECASE | re.DOTALL)
    if fence:
        text = fence.group(1).strip()

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start == -1 or end <= start:
            raise GraphRenderError("no JSON object found in graph response")
        try:
            return json.loads(text[start : end + 1])
        except json.JSONDecodeError as exc:
            raise GraphRenderError(f"invalid graph JSON: {exc}") from exc


def instruction_list(value):
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str):
        lines = [line.strip() for line in value.splitlines() if line.strip()]
        cleaned = [
            re.sub(r"^\s*(?:\d+[\).]|[-*•])\s*", "", line).strip()
            for line in lines
        ]
        return [line for line in cleaned if line]
    return []


def format_answer(data) -> str:
    if not isinstance(data, dict):
        raise GraphRenderError("graph response is not a JSON object")

    instructions = instruction_list(data.get("graph_instructions"))
    if not instructions:
        instructions = ["Draw the axes, plot the requested relationship, and label the key features."]

    answer = str(data.get("answer", "")).strip()
    if not answer:
        answer = "No useful response"

    lines = ["Graph instructions"]
    lines.extend(f"{number}. {step}" for number, step in enumerate(instructions, 1))
    lines.extend(["", "Answer", answer])
    return "\n".join(lines).strip()


def optional_float(value):
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def numeric_points(points):
    parsed = []
    if not isinstance(points, list):
        return parsed

    for point in points:
        if not isinstance(point, (list, tuple)) or len(point) < 2:
            continue
        x_value = optional_float(point[0])
        y_value = optional_float(point[1])
        if x_value is None or y_value is None:
            continue
        parsed.append((x_value, y_value))
    return parsed


def categorical_values(series):
    categories = series.get("categories")
    values = series.get("values")
    if not isinstance(categories, list) or not isinstance(values, list):
        return [], []

    labels = []
    numbers = []
    for category, value in zip(categories, values):
        numeric_value = optional_float(value)
        if numeric_value is None:
            continue
        labels.append(str(category))
        numbers.append(numeric_value)
    return labels, numbers


def import_pyplot():
    os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-cheater")
    os.makedirs(os.environ["MPLCONFIGDIR"], exist_ok=True)

    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    return plt


def render_graph(data, image_file: str):
    if not isinstance(data, dict):
        raise GraphRenderError("graph response is not a JSON object")

    graph = data.get("graph")
    if not isinstance(graph, dict):
        raise GraphRenderError("missing graph object")

    series_items = graph.get("series")
    if not isinstance(series_items, list) or not series_items:
        raise GraphRenderError("graph has no series")

    plt = import_pyplot()
    fig, ax = plt.subplots(figsize=(8, 5), dpi=160)

    default_kind = str(graph.get("kind", "line")).lower()
    categorical_x_labels = None
    plotted = False

    bar_series = [
        item
        for item in series_items
        if isinstance(item, dict) and categorical_values(item)[0]
    ]
    if bar_series:
        categorical_x_labels = categorical_values(bar_series[0])[0]
        bar_width = 0.8 / max(1, len(bar_series))
        base_positions = list(range(len(categorical_x_labels)))

        for index, item in enumerate(bar_series):
            labels, values = categorical_values(item)
            if labels != categorical_x_labels:
                continue
            offset = (index - (len(bar_series) - 1) / 2) * bar_width
            x_values = [position + offset for position in base_positions]
            ax.bar(
                x_values,
                values,
                width=bar_width,
                label=str(item.get("label", "")).strip() or None,
            )
            plotted = True

        ax.set_xticks(base_positions)
        ax.set_xticklabels(categorical_x_labels, rotation=20, ha="right")

    for item in series_items:
        if not isinstance(item, dict):
            continue
        if categorical_values(item)[0]:
            continue

        points = numeric_points(item.get("points"))
        if not points:
            continue

        x_values = [point[0] for point in points]
        y_values = [point[1] for point in points]
        label = str(item.get("label", "")).strip() or None
        kind = str(item.get("kind", default_kind)).lower()

        if kind == "scatter":
            ax.scatter(x_values, y_values, label=label)
        elif kind == "bar":
            ax.bar(x_values, y_values, label=label, width=0.6)
        else:
            marker = "o" if len(points) <= 12 else None
            ax.plot(x_values, y_values, marker=marker, label=label)
        plotted = True

    if not plotted:
        raise GraphRenderError("graph series had no plottable data")

    title = str(graph.get("title", "")).strip()
    x_label = str(graph.get("x_label", "")).strip()
    y_label = str(graph.get("y_label", "")).strip()
    if title:
        ax.set_title(title)
    if x_label:
        ax.set_xlabel(x_label)
    if y_label:
        ax.set_ylabel(y_label)

    x_min = optional_float(graph.get("x_min"))
    x_max = optional_float(graph.get("x_max"))
    y_min = optional_float(graph.get("y_min"))
    y_max = optional_float(graph.get("y_max"))
    if x_min is not None and x_max is not None and categorical_x_labels is None:
        ax.set_xlim(x_min, x_max)
    if y_min is not None and y_max is not None:
        ax.set_ylim(y_min, y_max)

    annotations = graph.get("annotations", [])
    if isinstance(annotations, list):
        for annotation in annotations:
            if not isinstance(annotation, dict):
                continue
            x_value = optional_float(annotation.get("x"))
            y_value = optional_float(annotation.get("y"))
            text = str(annotation.get("text", "")).strip()
            if x_value is None or y_value is None or not text:
                continue
            ax.annotate(text, (x_value, y_value), xytext=(5, 5), textcoords="offset points")

    handles, labels = ax.get_legend_handles_labels()
    if any(label for label in labels):
        ax.legend()

    ax.grid(True, alpha=0.25)
    fig.tight_layout()

    image_dir = os.path.dirname(image_file)
    if image_dir:
        os.makedirs(image_dir, exist_ok=True)
    fig.savefig(image_file, format="png", bbox_inches="tight")
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(
        description="Render a graph JSON response into answer text and a PNG image"
    )
    parser.add_argument(
        "--image-file",
        default=DEFAULT_GRAPH_IMAGE,
        help="Path where the rendered graph PNG should be written",
    )
    args = parser.parse_args()

    try:
        data = extract_json(sys.stdin.read())
        print(format_answer(data))
        render_graph(data, args.image_file)
    except (OSError, GraphRenderError, ImportError, ValueError) as exc:
        print(f"Graph rendering failed: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
