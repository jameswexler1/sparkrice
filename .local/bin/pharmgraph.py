#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from urllib.parse import urlparse

import requests


DAILYMED_API_ROOT = "https://dailymed.nlm.nih.gov/dailymed/services/v2"
NCBI_EUTILS_ROOT = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
PMC_INSTANCE_ROOT = "https://pmc.ncbi.nlm.nih.gov/articles/instance"
REQUEST_TIMEOUT = 20
AI_TIMEOUT = 75
MAX_IMAGE_BYTES = 20 * 1024 * 1024
DEFAULT_IMAGE_FILE = "/tmp/cheater_pharm_graph.png"
DEFAULT_PLOT_DIR = "/home/gustavo/assistance/plots"
DEFAULT_PLOT_DB_FILE = os.path.join(DEFAULT_PLOT_DIR, "plots.json")
MIN_LOCAL_PLOT_CONFIDENCE = 0.55

CHART_WORDS = {
    "auc",
    "bar",
    "bioavailability",
    "chart",
    "clearance",
    "cmax",
    "concentration",
    "curve",
    "dose",
    "effect",
    "exposure",
    "figure",
    "graph",
    "half-life",
    "kinetic",
    "pharmacodynamic",
    "pharmacodynamics",
    "pharmacokinetic",
    "pharmacokinetics",
    "plasma",
    "plot",
    "profile",
    "receptor",
    "response",
    "serum",
    "tmax",
    "time",
}

NEGATIVE_IMAGE_WORDS = {
    "blister",
    "bottle",
    "capsule",
    "carton",
    "chemical structure",
    "container",
    "imprint",
    "label",
    "molecular structure",
    "package",
    "structural formula",
    "tablet",
    "vial",
}


class PharmGraphError(Exception):
    pass


@dataclass
class ChartCandidate:
    source: str
    url: str
    score: int
    caption: str = ""
    title: str = ""
    name: str = ""


@dataclass
class LocalPlot:
    plot_id: str
    file_path: str
    title: str = ""
    description: str = ""
    keywords: list[str] | None = None
    graph_instructions: list[str] | None = None


def extract_json(raw: str):
    text = raw.strip()
    if not text:
        raise PharmGraphError("empty AI response")

    fenced = re.search(r"```(?:json)?\s*(.*?)\s*```", text, re.IGNORECASE | re.DOTALL)
    if fenced:
        text = fenced.group(1).strip()

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start == -1 or end <= start:
            raise PharmGraphError("AI response did not contain a JSON object")
        try:
            return json.loads(text[start : end + 1])
        except json.JSONDecodeError as exc:
            raise PharmGraphError(f"invalid AI JSON: {exc}") from exc


def as_text_list(value):
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str) and value.strip():
        return [value.strip()]
    return []


def clean_text(text: str) -> str:
    text = re.sub(r"https?://\S+", "", str(text))
    text = re.sub(r"\s+", " ", text).strip()
    return text


def graph_instructions(data):
    instructions = as_text_list(data.get("graph_instructions") if isinstance(data, dict) else None)
    cleaned = []
    for instruction in instructions:
        instruction = clean_text(
            re.sub(r"^\s*(?:\d+[\).]|[-*•])\s*", "", instruction)
        )
        if instruction:
            cleaned.append(instruction)
    return cleaned


def format_answer(data, chart_found: bool) -> str:
    if not isinstance(data, dict):
        raise PharmGraphError("final answer data is not a JSON object")

    instructions = graph_instructions(data)
    if not instructions:
        instructions = [
            "Draw the axes requested by the question.",
            "Use the pharmacologic relationship described in the answer to shape the curve.",
            "Label the key trend and any important pharmacokinetic or pharmacodynamic points.",
        ]

    if not chart_found:
        instructions.insert(
            0,
            "No source-backed chart image was found automatically; draw the graph from the steps below.",
        )

    answer = clean_text(data.get("answer", ""))
    if not answer:
        answer = "No useful response"

    lines = ["Graph instructions"]
    lines.extend(f"{number}. {step}" for number, step in enumerate(instructions, 1))
    lines.extend(["", "Answer", answer])
    return "\n".join(lines).strip()


def normalize_plot_entry(entry, db_dir: str):
    if not isinstance(entry, dict):
        return None

    plot_id = clean_text(entry.get("id", ""))
    file_name = str(entry.get("file", "")).strip()
    if not plot_id or not file_name:
        return None

    file_path = file_name
    if not os.path.isabs(file_path):
        file_path = os.path.normpath(os.path.join(db_dir, file_path))

    return LocalPlot(
        plot_id=plot_id,
        file_path=file_path,
        title=clean_text(entry.get("title", "")),
        description=clean_text(entry.get("description", "")),
        keywords=unique_texts(entry.get("keywords", []), limit=30),
        graph_instructions=graph_instructions(entry),
    )


def load_plot_database(db_path: str):
    if not db_path or not os.path.isfile(db_path):
        return []

    try:
        with open(db_path, "r", encoding="utf-8") as db_file:
            raw = json.load(db_file)
    except (OSError, json.JSONDecodeError):
        return []

    entries = raw.get("plots", raw) if isinstance(raw, dict) else raw
    if not isinstance(entries, list):
        return []

    db_dir = os.path.dirname(os.path.abspath(db_path))
    plots = []
    seen = set()
    for entry in entries:
        plot = normalize_plot_entry(entry, db_dir)
        if not plot or plot.plot_id in seen:
            continue
        plots.append(plot)
        seen.add(plot.plot_id)
    return plots


def plot_database_prompt_payload(plots):
    payload = []
    for plot in plots:
        payload.append(
            {
                "id": plot.plot_id,
                "title": plot.title,
                "description": plot.description,
                "keywords": plot.keywords or [],
                "graph_instructions": plot.graph_instructions or [],
            }
        )
    return payload


def plot_lookup(plots):
    return {plot.plot_id: plot for plot in plots}


def selected_local_plot(selection, plots, min_confidence: float = MIN_LOCAL_PLOT_CONFIDENCE):
    selected = selected_local_plots(selection, plots, min_confidence=min_confidence)
    return selected[0] if selected else None


def selected_plot_ids(selection):
    if not isinstance(selection, dict):
        return []

    raw_plot_ids = selection.get("plot_ids")
    if raw_plot_ids is None:
        raw_plot_ids = selection.get("plot_id")

    if isinstance(raw_plot_ids, list):
        values = raw_plot_ids
    else:
        values = [raw_plot_ids]

    plot_ids = []
    seen = set()
    for value in values:
        if value is None:
            continue
        plot_id = clean_text(value)
        if not plot_id or plot_id.lower() in {"none", "null", "no_match"}:
            continue
        if plot_id in seen:
            continue
        plot_ids.append(plot_id)
        seen.add(plot_id)
    return plot_ids


def selected_local_plots(selection, plots, min_confidence: float = MIN_LOCAL_PLOT_CONFIDENCE):
    if not isinstance(selection, dict):
        return []

    try:
        confidence = float(selection.get("confidence", 0))
    except (TypeError, ValueError):
        confidence = 0

    if confidence < min_confidence:
        return []

    lookup = plot_lookup(plots)
    selected = []
    for plot_id in selected_plot_ids(selection):
        plot = lookup.get(plot_id)
        if plot and os.path.isfile(plot.file_path):
            selected.append(plot)
    return selected


def copy_local_plot_image(plot: LocalPlot, image_file: str):
    image_dir = os.path.dirname(image_file) or "."
    os.makedirs(image_dir, exist_ok=True)

    fd, tmp_path = tempfile.mkstemp(prefix=".localplot-", dir=image_dir)
    os.close(fd)
    try:
        shutil.copyfile(plot.file_path, tmp_path)
        if os.path.getsize(tmp_path) == 0:
            raise PharmGraphError("local plot image is empty")
        os.replace(tmp_path, image_file)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def select_local_plots(question: str, plots, planner: str, question_image: str, context_file: str):
    if not plots:
        return [], None

    prompt = (
        "Original question:\n"
        f"{question}\n\n"
        "Available local plot database JSON:\n"
        f"{json.dumps(plot_database_prompt_payload(plots), ensure_ascii=False, indent=2)}"
    )
    selection = run_ai(
        planner,
        "plot_db_select",
        prompt,
        image_file=question_image,
        context_file=context_file,
    )
    selected = selected_local_plots(selection, plots)
    return selected, selection


def select_local_plot(question: str, plots, planner: str, question_image: str, context_file: str):
    selected, selection = select_local_plots(
        question,
        plots,
        planner,
        question_image,
        context_file,
    )
    return (selected[0] if selected else None), selection


def write_image_list(image_list_file: str, image_paths):
    if not image_list_file:
        return

    image_dir = os.path.dirname(image_list_file) or "."
    os.makedirs(image_dir, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".pharmgraph-images-", dir=image_dir)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp_file:
            for image_path in image_paths:
                if image_path:
                    tmp_file.write(f"{image_path}\n")
        os.replace(tmp_path, image_list_file)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def run_ai(planner: str, model: str, prompt: str, image_file: str = "", context_file: str = ""):
    command = [planner, "--model", model]
    if image_file:
        command.extend(["--image-file", image_file])
    if context_file:
        command.extend(["--context-file", context_file])

    try:
        result = subprocess.run(
            command,
            input=prompt,
            text=True,
            capture_output=True,
            timeout=AI_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise PharmGraphError(f"AI planner failed: {type(exc).__name__}") from exc

    output = result.stdout.strip()
    if result.returncode != 0:
        detail = result.stderr.strip() or "non-zero exit"
        raise PharmGraphError(f"AI planner failed: {detail}")
    if output in {"API error — try again", "No useful response"}:
        raise PharmGraphError(output)
    return extract_json(output)


def unique_texts(values, limit=12):
    seen = set()
    unique = []
    for value in values:
        text = clean_text(value)
        key = text.lower()
        if text and key not in seen:
            unique.append(text)
            seen.add(key)
        if len(unique) >= limit:
            break
    return unique


def plan_terms(plan, question: str):
    if not isinstance(plan, dict):
        return {
            "drug_names": [],
            "search_terms": [question],
            "chart_keywords": list(CHART_WORDS),
        }

    drug_names = unique_texts(plan.get("drug_names", []), limit=6)
    search_terms = unique_texts(plan.get("search_terms", []), limit=10)
    chart_keywords = unique_texts(plan.get("chart_keywords", []), limit=12)
    if not search_terms:
        search_terms = [question]
    if not chart_keywords:
        chart_keywords = list(CHART_WORDS)

    return {
        "drug_names": drug_names,
        "search_terms": search_terms,
        "chart_keywords": chart_keywords,
    }


def word_tokens(text: str):
    return re.findall(r"[a-zA-Z][a-zA-Z0-9-]{2,}", text.lower())


def score_text(text: str, plan, question: str) -> int:
    terms = plan_terms(plan, question)
    searchable = clean_text(text).lower()
    score = 0

    phrases = unique_texts(
        terms["drug_names"] + terms["search_terms"] + terms["chart_keywords"],
        limit=28,
    )
    for phrase in phrases:
        phrase_lower = phrase.lower()
        if not phrase_lower:
            continue
        if phrase_lower in searchable:
            score += 9 if " " in phrase_lower else 5

    for token in set(word_tokens(" ".join(phrases))):
        if token in searchable:
            score += 1

    for word in CHART_WORDS:
        if word in searchable:
            score += 5

    for word in NEGATIVE_IMAGE_WORDS:
        if word in searchable:
            score -= 8

    return score


def mentions_plan_drug(text: str, plan, question: str) -> bool:
    drug_names = plan_terms(plan, question)["drug_names"]
    if not drug_names:
        return True

    searchable = clean_text(text).lower()
    for drug_name in drug_names:
        drug_lower = drug_name.lower()
        if drug_lower and drug_lower in searchable:
            return True

        tokens = word_tokens(drug_name)
        if tokens and all(token in searchable for token in tokens):
            return True

    return False


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def element_text(element) -> str:
    return clean_text(" ".join(part for part in element.itertext() if part))


def parse_dailymed_media_captions(xml_text: str):
    captions = {}
    if not xml_text.strip():
        return captions

    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return captions

    for element in root.iter():
        if local_name(element.tag) != "observationMedia":
            continue

        reference = ""
        for child in element.iter():
            if local_name(child.tag) == "reference":
                reference = child.attrib.get("value", "")
                break

        if reference:
            captions[reference] = element_text(element)

    return captions


def dailymed_spls(session, drug_names):
    results = []
    seen = set()
    for drug_name in drug_names[:5]:
        try:
            response = session.get(
                f"{DAILYMED_API_ROOT}/spls.json",
                params={"drug_name": drug_name, "pagesize": 5},
                timeout=REQUEST_TIMEOUT,
            )
            response.raise_for_status()
            data = response.json()
        except (requests.RequestException, ValueError):
            continue

        for item in data.get("data", []):
            setid = item.get("setid")
            if not setid or setid in seen:
                continue
            seen.add(setid)
            results.append(
                {
                    "setid": setid,
                    "title": item.get("title", ""),
                }
            )
    return results


def dailymed_media_candidates(session, spl, plan, question: str):
    setid = spl["setid"]
    title = spl.get("title", "")

    try:
        media_response = session.get(
            f"{DAILYMED_API_ROOT}/spls/{setid}/media.json",
            timeout=REQUEST_TIMEOUT,
        )
        media_response.raise_for_status()
        media_data = media_response.json()
    except (requests.RequestException, ValueError):
        return []

    captions = {}
    try:
        xml_response = session.get(
            f"{DAILYMED_API_ROOT}/spls/{setid}.xml",
            timeout=REQUEST_TIMEOUT,
        )
        xml_response.raise_for_status()
        captions = parse_dailymed_media_captions(xml_response.text)
    except requests.RequestException:
        captions = {}

    media_items = media_data.get("data", {}).get("media", [])
    candidates = []
    for item in media_items:
        mime_type = item.get("mime_type", "")
        if not mime_type.startswith("image/"):
            continue

        name = item.get("name", "")
        caption = captions.get(name, "")
        url = item.get("url", "")
        if not url:
            continue

        scored_text = f"{title} {name} {caption}"
        if not mentions_plan_drug(scored_text, plan, question):
            continue

        score = score_text(scored_text, plan, question) + 3
        if score < 10:
            continue

        candidates.append(
            ChartCandidate(
                source="DailyMed",
                url=url,
                score=score,
                caption=caption,
                title=title,
                name=name,
            )
        )
    return candidates


def build_pmc_query(plan, question: str) -> str:
    terms = plan_terms(plan, question)
    phrases = unique_texts(
        terms["drug_names"] + terms["search_terms"] + terms["chart_keywords"],
        limit=10,
    )
    if not phrases:
        phrases = [question]

    query = " ".join(phrases)
    query = re.sub(r"[^A-Za-z0-9 +/_().-]", " ", query)
    query = re.sub(r"\s+", " ", query).strip()
    if not re.search(r"\bpharmaco", query, re.IGNORECASE):
        query = f"{query} pharmacokinetics pharmacodynamics"
    if not re.search(r"\b(?:figure|graph|chart|plot|curve)\b", query, re.IGNORECASE):
        query = f"{query} figure graph"
    return query


def pmc_search_ids(session, plan, question: str):
    query = build_pmc_query(plan, question)
    try:
        response = session.get(
            f"{NCBI_EUTILS_ROOT}/esearch.fcgi",
            params={
                "db": "pmc",
                "term": f"{query} open access[filter]",
                "retmode": "json",
                "retmax": 8,
                "tool": "cheater_pharmgraph",
                "email": "gustavo@local",
            },
            timeout=REQUEST_TIMEOUT,
        )
        response.raise_for_status()
        data = response.json()
    except (requests.RequestException, ValueError):
        return []

    return data.get("esearchresult", {}).get("idlist", [])


def graphic_href(element):
    for key, value in element.attrib.items():
        if key == "href" or key.endswith("}href"):
            return value
    return ""


def parse_pmc_figure_candidates(xml_text: str, pmc_id: str, plan, question: str):
    if not xml_text.strip():
        return []

    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return []

    article_title = ""
    for element in root.iter():
        if local_name(element.tag) == "article-title":
            article_title = element_text(element)
            break

    candidates = []
    for fig in root.iter():
        if local_name(fig.tag) != "fig":
            continue

        caption = element_text(fig)
        graphics = [
            graphic_href(element)
            for element in fig.iter()
            if local_name(element.tag) == "graphic" and graphic_href(element)
        ]
        if not graphics:
            continue

        scored_text = f"{article_title} {caption}"
        if not mentions_plan_drug(scored_text, plan, question):
            continue

        score = score_text(scored_text, plan, question)
        if score < 10:
            continue

        for href in graphics:
            candidates.append(
                ChartCandidate(
                    source="PMC Open Access",
                    url=f"{PMC_INSTANCE_ROOT}/{pmc_id}/bin/{href}",
                    score=score,
                    caption=caption,
                    title=article_title,
                    name=href,
                )
            )
    return candidates


def pmc_candidates(session, plan, question: str):
    candidates = []
    for pmc_id in pmc_search_ids(session, plan, question):
        try:
            response = session.get(
                f"{NCBI_EUTILS_ROOT}/efetch.fcgi",
                params={
                    "db": "pmc",
                    "id": pmc_id,
                    "retmode": "xml",
                    "tool": "cheater_pharmgraph",
                    "email": "gustavo@local",
                },
                timeout=REQUEST_TIMEOUT,
            )
            response.raise_for_status()
        except requests.RequestException:
            continue

        candidates.extend(parse_pmc_figure_candidates(response.text, pmc_id, plan, question))
        if len(candidates) >= 10:
            break
    return candidates


def safe_image_extension(url: str, content_type: str):
    path = urlparse(url).path.lower()
    for extension in (".png", ".jpg", ".jpeg", ".gif", ".webp"):
        if path.endswith(extension):
            return extension
    if "png" in content_type:
        return ".png"
    if "gif" in content_type:
        return ".gif"
    if "webp" in content_type:
        return ".webp"
    return ".jpg"


def download_image(session, candidate: ChartCandidate, image_file: str):
    try:
        response = session.get(candidate.url, stream=True, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
    except requests.RequestException as exc:
        raise PharmGraphError(f"image download failed: {type(exc).__name__}") from exc

    content_type = response.headers.get("content-type", "").lower()
    if not content_type.startswith("image/"):
        raise PharmGraphError(f"source did not return an image: {content_type or 'unknown'}")

    image_dir = os.path.dirname(image_file) or "."
    os.makedirs(image_dir, exist_ok=True)
    suffix = safe_image_extension(candidate.url, content_type)
    total = 0

    fd, tmp_path = tempfile.mkstemp(prefix=".pharmgraph-", suffix=suffix, dir=image_dir)
    try:
        with os.fdopen(fd, "wb") as tmp_file:
            for chunk in response.iter_content(chunk_size=64 * 1024):
                if not chunk:
                    continue
                total += len(chunk)
                if total > MAX_IMAGE_BYTES:
                    raise PharmGraphError("source image is too large")
                tmp_file.write(chunk)

        if total == 0:
            raise PharmGraphError("source image was empty")

        os.replace(tmp_path, image_file)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def find_source_chart(question: str, plan, image_file: str):
    session = requests.Session()
    session.headers.update(
        {
            "User-Agent": "cheater-pharmgraph/1.0 (+local educational script)",
            "Accept": "application/json, application/xml, image/*;q=0.9, */*;q=0.8",
        }
    )

    terms = plan_terms(plan, question)
    candidates = []

    for spl in dailymed_spls(session, terms["drug_names"]):
        candidates.extend(dailymed_media_candidates(session, spl, plan, question))

    candidates.extend(pmc_candidates(session, plan, question))
    candidates.sort(key=lambda candidate: candidate.score, reverse=True)

    errors = []
    for candidate in candidates:
        try:
            download_image(session, candidate, image_file)
            return candidate
        except PharmGraphError as exc:
            errors.append(f"{candidate.source}:{candidate.name}:{exc}")
            continue

    if errors:
        print("Pharm graph image candidates failed: " + " | ".join(errors[:3]), file=sys.stderr)
    return None


def main():
    parser = argparse.ArgumentParser(
        description="Find a source-backed pharmacology chart and format graph answer text"
    )
    parser.add_argument(
        "--planner",
        default=os.environ.get("ASKGEMINI", "./askgemini.py"),
        help="Path to askgemini.py or another compatible planner",
    )
    parser.add_argument(
        "--question-image",
        default="",
        help="Original question screenshot to help extract drug/topic names",
    )
    parser.add_argument(
        "--context-file",
        default="",
        help="Optional context file passed to the planner",
    )
    parser.add_argument(
        "--image-file",
        default=DEFAULT_IMAGE_FILE,
        help="Where the source-backed graph image should be written",
    )
    parser.add_argument(
        "--image-list-file",
        default="",
        help="Optional file where every selected graph image path is written, one per line",
    )
    parser.add_argument(
        "--plot-db",
        default=DEFAULT_PLOT_DB_FILE,
        help="Path to local plot metadata JSON",
    )
    args = parser.parse_args()

    question = sys.stdin.read().strip()
    if not question:
        return 0

    local_plots = load_plot_database(args.plot_db)
    local_selection = None
    if local_plots:
        try:
            local_selected_plots, local_selection = select_local_plots(
                question,
                local_plots,
                args.planner,
                args.question_image,
                args.context_file,
            )
            if local_selected_plots:
                selected_paths = [plot.file_path for plot in local_selected_plots]
                write_image_list(args.image_list_file, selected_paths)
                copy_local_plot_image(local_selected_plots[0], args.image_file)
                print(
                    "Pharm graph local plots selected: "
                    + ", ".join(plot.plot_id for plot in local_selected_plots),
                    file=sys.stderr,
                )
                print(format_answer(local_selection, chart_found=True))
                return 0
        except PharmGraphError as exc:
            print(f"Pharm graph local plot lookup skipped: {exc}", file=sys.stderr)

    try:
        plan = run_ai(
            args.planner,
            "pharm_graph_plan",
            question,
            image_file=args.question_image,
            context_file=args.context_file,
        )
    except PharmGraphError as exc:
        print(f"Pharmacology graph failed: {exc}", file=sys.stderr)
        return 1

    candidate = find_source_chart(question, plan, args.image_file)
    final_data = plan

    if candidate:
        write_image_list(args.image_list_file, [args.image_file])
        print(
            f"Pharm graph source image selected from {candidate.source}: {candidate.name}",
            file=sys.stderr,
        )
        try:
            final_data = run_ai(
                args.planner,
                "pharm_graph_final",
                f"Original question:\n{question}\n\nUse the attached pharmacology chart image.",
                image_file=args.image_file,
                context_file=args.context_file,
            )
        except PharmGraphError as exc:
            print(f"Pharm graph final formatting fell back to initial plan: {exc}", file=sys.stderr)

    try:
        print(format_answer(final_data, chart_found=bool(candidate)))
    except PharmGraphError as exc:
        print(f"Pharmacology graph failed: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
