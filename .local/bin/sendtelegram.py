#!/usr/bin/env python3
import argparse
import fcntl
import os
import sys

import requests


TELEGRAM_API_ROOT = "https://api.telegram.org"
TELEGRAM_MESSAGE_LIMIT = 4096
TELEGRAM_TIMEOUT = 10
DEFAULT_COUNTER_FILE = "/tmp/cheater_telegram_counter"
CONFIGURED_BOT_TOKEN = "8826289876:AAHQynhRjINBdb52aJt-bvKBIVhezET296E"
# CONFIGURED_CHAT_IDS = ["1500669410", "500742282"]
CONFIGURED_CHAT_IDS = ["1500669410"]


class TelegramError(Exception):
    pass


def format_message(number: int, question: str, answer: str) -> str:
    question = question.strip()
    answer = answer.strip()
    if not question:
        raise TelegramError("Question is empty")
    if not answer:
        raise TelegramError("Answer is empty")
    return f"Question {number}: {question}\n\nANSWER: {answer}"


def split_message(message: str, limit: int = TELEGRAM_MESSAGE_LIMIT):
    if limit < 1:
        raise ValueError("Message limit must be positive")

    chunks = []
    remaining = message
    while len(remaining) > limit:
        split_at = remaining.rfind("\n", 0, limit + 1)
        if split_at <= 0:
            split_at = limit
        else:
            split_at += 1
        chunks.append(remaining[:split_at])
        remaining = remaining[split_at:]
    if remaining:
        chunks.append(remaining)
    return chunks


def parse_chat_ids(value: str):
    chat_ids = []
    seen = set()
    for chat_id in value.replace(",", " ").split():
        if chat_id not in seen:
            chat_ids.append(chat_id)
            seen.add(chat_id)
    return chat_ids


def configured_chat_ids():
    env_chat_ids = os.environ.get("TELEGRAM_CHAT_IDS") or os.environ.get(
        "TELEGRAM_CHAT_ID", ""
    )
    if env_chat_ids:
        return parse_chat_ids(env_chat_ids)
    return CONFIGURED_CHAT_IDS


def configured_bot_token():
    return os.environ.get("TELEGRAM_BOT_TOKEN") or CONFIGURED_BOT_TOKEN


def send_message(token: str, chat_id: str, message: str):
    url = f"{TELEGRAM_API_ROOT}/bot{token}/sendMessage"
    for chunk in split_message(message):
        try:
            response = requests.post(
                url,
                json={"chat_id": chat_id, "text": chunk},
                timeout=TELEGRAM_TIMEOUT,
            )
        except requests.RequestException as exc:
            # Do not include the request URL in the error: it contains the bot token.
            raise TelegramError(
                f"Telegram request failed ({type(exc).__name__})"
            ) from exc

        try:
            result = response.json()
        except ValueError as exc:
            raise TelegramError(
                f"Telegram returned HTTP {response.status_code} with an invalid response"
            ) from exc

        if response.status_code != 200 or not result.get("ok"):
            description = result.get("description", "unknown Telegram API error")
            raise TelegramError(
                f"Telegram returned HTTP {response.status_code}: {description}"
            )


def send_photo(token: str, chat_id: str, image_file: str, caption: str = ""):
    if not os.path.isfile(image_file):
        raise TelegramError(f"Telegram image file does not exist: {image_file}")

    url = f"{TELEGRAM_API_ROOT}/bot{token}/sendPhoto"
    data = {"chat_id": chat_id}
    if caption:
        data["caption"] = caption[:1024]

    try:
        with open(image_file, "rb") as photo:
            response = requests.post(
                url,
                data=data,
                files={"photo": photo},
                timeout=TELEGRAM_TIMEOUT,
            )
    except OSError as exc:
        raise TelegramError(f"Could not read Telegram image file: {image_file}") from exc
    except requests.RequestException as exc:
        # Do not include the request URL in the error: it contains the bot token.
        raise TelegramError(
            f"Telegram photo request failed ({type(exc).__name__})"
        ) from exc

    try:
        result = response.json()
    except ValueError as exc:
        raise TelegramError(
            f"Telegram returned HTTP {response.status_code} with an invalid photo response"
        ) from exc

    if response.status_code != 200 or not result.get("ok"):
        description = result.get("description", "unknown Telegram API error")
        raise TelegramError(
            f"Telegram photo returned HTTP {response.status_code}: {description}"
        )


def read_counter(counter_file) -> int:
    counter_file.seek(0)
    value = counter_file.read().strip()
    try:
        return max(0, int(value)) if value else 0
    except ValueError:
        return 0


def send_to_chats(token: str, chat_ids, message: str, image_files=None, photo_caption: str = ""):
    image_files = image_files or []
    for chat_id in chat_ids:
        send_message(token, chat_id, message)
        for index, image_file in enumerate(image_files, 1):
            caption = photo_caption
            if len(image_files) > 1 and photo_caption:
                caption = f"{photo_caption} {index}/{len(image_files)}"
            send_photo(token, chat_id, image_file, caption)


def notify(
    question: str,
    answer: str,
    token: str,
    chat_ids,
    counter_path: str,
    image_files=None,
):
    if not token:
        raise TelegramError("TELEGRAM_BOT_TOKEN is not configured")
    if not chat_ids:
        raise TelegramError("TELEGRAM_CHAT_IDS or TELEGRAM_CHAT_ID is not configured")

    with open(counter_path, "a+", encoding="utf-8") as counter_file:
        os.fchmod(counter_file.fileno(), 0o600)
        fcntl.flock(counter_file.fileno(), fcntl.LOCK_EX)

        number = read_counter(counter_file) + 1
        message = format_message(number, question, answer)
        image_files = [image_file for image_file in (image_files or []) if image_file]
        if image_files:
            send_to_chats(
                token,
                chat_ids,
                message,
                image_files=image_files,
                photo_caption=f"Question {number} graph",
            )
        else:
            send_to_chats(token, chat_ids, message)

        # Advance the counter only after Telegram accepts every message chunk.
        counter_file.seek(0)
        counter_file.truncate()
        counter_file.write(str(number))
        counter_file.flush()
        os.fsync(counter_file.fileno())
        return number


def read_payload():
    payload = sys.stdin.buffer.read()
    parts = payload.split(b"\0", 1)
    if len(parts) != 2:
        raise TelegramError("Expected question and answer separated by a NUL byte")
    try:
        return parts[0].decode("utf-8"), parts[1].decode("utf-8")
    except UnicodeDecodeError as exc:
        raise TelegramError("Question or answer is not valid UTF-8") from exc


def main():
    parser = argparse.ArgumentParser(
        description="Send a question and answer to fixed Telegram chats"
    )
    parser.add_argument(
        "--counter-file",
        default=os.environ.get("TELEGRAM_COUNTER_FILE", DEFAULT_COUNTER_FILE),
        help="Temporary question counter path",
    )
    parser.add_argument(
        "--image-file",
        action="append",
        default=[],
        help="Optional image to send after the text answer",
    )
    args = parser.parse_args()

    try:
        question, answer = read_payload()
        number = notify(
            question=question,
            answer=answer,
            token=configured_bot_token(),
            chat_ids=configured_chat_ids(),
            counter_path=args.counter_file,
            image_files=args.image_file,
        )
    except (OSError, TelegramError) as exc:
        print(f"Telegram notification failed: {exc}", file=sys.stderr)
        return 1

    print(f"Telegram notification sent as question {number}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
