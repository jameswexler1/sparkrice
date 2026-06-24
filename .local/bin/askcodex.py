#!/usr/bin/env python3
import sys
import argparse
import subprocess
import re


def detect_question_type(text: str):
    text = re.sub(r'^[A-Z]{9,}$\n?', '', text, flags=re.MULTILINE)
    if (
        re.search(r"\b[A-D]\)", text)
        or re.search(r'^\s*[-•*]\s+[A-Za-z]', text, flags=re.MULTILINE)
        or re.search(r'^\s*\d+\.\s+[A-Za-z]', text, flags=re.MULTILINE)
    ):
        return "flash"
    return "pro"


def instruction_for(model: str):
    if model == "flash":
        return "Just the answer (e.g., 'Ribavirin'). Be concise—no explanation."
    if model == "pro":
        return "Answer briefly: the key fact or choice only."
    return (
        "Answer as a top student would in an exam. "
        "For open/dissertative questions (explain, discuss, analyse, evaluate, compare, "
        "to what extent, etc.), give a complete, well-structured response. "
        "Use paragraphs or bullet points as appropriate. "
        "Include key arguments, explanations, relevant examples/evidence, and be thorough "
        "but clear. Aim for full marks. "
        "But don't overextend — write like a student answering on paper."
    )


def query_codex(prompt: str, model: str):
    # Instruction goes as the CLI argument; question is piped as context
    result = subprocess.run(
        ["codex", "exec", "--skip-git-repo-check", instruction_for(model)],
        input=prompt,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        return f"Codex error:\n{result.stderr.strip()}"

    answer = result.stdout.strip()
    answer = re.sub(r'\n\s*\n+', '\n', answer).strip()
    return answer or "No useful response"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", choices=["flash", "pro", "open"])
    args = parser.parse_args()

    prompt = sys.stdin.read().strip()
    if not prompt:
        sys.exit(0)

    model = args.model or ("flash" if detect_question_type(prompt) == "flash" else "pro")
    print(query_codex(prompt, model))


if __name__ == "__main__":
    main()
