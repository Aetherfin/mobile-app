import os
import sys
import json
import glob
import subprocess
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from urllib.parse import urlencode

# Read environment variables set by GitHub Actions
BOT_TOKEN = os.environ.get('TG_BOT_TOKEN')
CHAT_ID = os.environ.get('TG_CHAT_ID')

if not BOT_TOKEN or not CHAT_ID:
    print("Error: TG_BOT_TOKEN and TG_CHAT_ID environment variables must be set.")
    sys.exit(1)


def send_request(url, data=None, headers=None, timeout=30):
    if headers is None:
        headers = {}
    req = Request(url, data=data, headers=headers)
    try:
        with urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except HTTPError as e:
        print(f"HTTP Error {e.code}: {e.read().decode('utf-8')}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


def get_header(icon="\U0001f528"):
    """Build the message header with build context."""
    branch = os.environ.get('TG_BRANCH', 'unknown')
    build_id = os.environ.get('TG_BUILD_ID', 'unknown')
    mode = os.environ.get('TG_MODE', '')
    actor = os.environ.get('TG_ACTOR', 'unknown')
    tag = os.environ.get('TG_TAG', '')
    sha = os.environ.get('TG_SHA', '')
    commit = os.environ.get('TG_COMMIT', '')
    timestamp = os.environ.get('TG_TIMESTAMP', '')

    parts = [f"{icon} <b>Aetherfin {'Release' if tag else 'Build'}</b>"]

    if tag:
        parts.append(f"<b>Tag:</b> <code>{tag}</code>")
    parts.append(f"<b>Branch:</b> <code>{branch}</code>")
    if mode:
        parts.append(f"<b>Mode:</b> <code>{mode}</code>")
    parts.append(f"<b>Build ID:</b> <code>{build_id}</code>")
    if sha and commit:
        parts.append("\u2500" * 12)
        parts.append(f"<b>Last Commit:</b>")
        parts.append(f"<code>{sha}</code> \u2014 {commit}")
    parts.append(f"<b>Triggered by:</b> <code>{actor}</code>")
    parts.append("\u2500" * 12)
    if timestamp:
        parts.append(f"<i>{timestamp}</i>")

    return "\n".join(parts)


def build_message(status_text, icon="\U0001f528"):
    """Combine header + status block."""
    header = get_header(icon)
    if status_text:
        return f"{header}\n<blockquote>{status_text}</blockquote>"
    return header


def _delete_message(msg_id):
    """Delete a message by ID. Silently ignores failures."""
    if not msg_id:
        return
    try:
        url = f"https://api.telegram.org/bot{BOT_TOKEN}/deleteMessage"
        payload = json.dumps({
            "chat_id": CHAT_ID,
            "message_id": int(msg_id)
        }).encode('utf-8')
        headers = {"Content-Type": "application/json"}
        req = Request(url, data=payload, headers=headers)
        urlopen(req, timeout=10)
        print(f"Deleted message {msg_id}.")
    except Exception as e:
        print(f"Warning: Failed to delete message {msg_id}: {e}")


def _send_text(text, reply_markup=None):
    """Send a new text message. Returns the message ID."""
    payload = {
        "chat_id": CHAT_ID,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    data = json.dumps(payload).encode('utf-8')
    headers = {"Content-Type": "application/json"}

    result = send_request(url, data=data, headers=headers)
    if result.get('ok'):
        new_id = result['result']['message_id']
        print(f"Sent message {new_id}.")
        return new_id
    else:
        print(f"Failed to send message: {result}")
        sys.exit(1)


def _upload_to_0x0(file_path):
    filename = os.path.basename(file_path)

    try:
        result = subprocess.run(
            ["curl", "-s", "-F", "reqtype=fileupload", "-F", f"fileToUpload=@{file_path}", "https://litterbox.catbox.moe/resources/internals/api.php"],
            capture_output=True,
            text=True,
            timeout=300
        )
        if result.returncode == 0:
            url = result.stdout.strip()
            if url.startswith("http"):
                print(f"Uploaded to catbox: {url}")
                return url
            else:
                print(f"Unexpected catbox response: {url}")
                return None
        else:
            print(f"curl failed: {result.stderr}")
            return None
    except subprocess.TimeoutExpired:
        print("Upload to catbox timed out")
        return None
    except Exception as e:
        print(f"Error uploading to catbox: {e}")
        return None


def init_message():
    """Send the 'Build started' message. Saves message ID to GITHUB_ENV."""
    text = build_message("\U0001f527 Build started...")
    msg_id = _send_text(text)
    print(f"TG_MESSAGE_ID={msg_id}")
    github_env = os.environ.get('GITHUB_ENV')
    if github_env:
        with open(github_env, 'a') as f:
            f.write(f"TG_MESSAGE_ID={msg_id}\n")


def update_message():
    """Edit the existing init message with updated progress status."""
    msg_id = os.environ.get('TG_MESSAGE_ID')
    status_text = os.environ.get('TG_STATUS_TEXT', '')

    if not msg_id:
        print("Warning: TG_MESSAGE_ID not set — skipping progress update.")
        return

    icon = os.environ.get('TG_ICON', '\U0001f528')
    text = build_message(status_text, icon=icon)

    payload = {
        "chat_id": CHAT_ID,
        "message_id": int(msg_id),
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/editMessageText"
    data = json.dumps(payload).encode('utf-8')
    headers = {"Content-Type": "application/json"}

    try:
        result = send_request(url, data=data, headers=headers)
        if result.get('ok'):
            print(f"Updated message {msg_id} to: {status_text}")
        else:
            print(f"Warning: Failed to update message: {result}")
    except Exception as e:
        print(f"Warning: Telegram editMessageText failed: {e}")


def success_message():
    msg_id = os.environ.get('TG_MESSAGE_ID')

    # Delete the progress message first
    _delete_message(msg_id)

    tag = os.environ.get('TG_TAG', '')
    apk_dir = os.environ.get('TG_APK_DIR', 'build/app/outputs/flutter-apk')
    run_url = os.environ.get('TG_RUN_URL', '')
    commit_url = os.environ.get('TG_COMMIT_URL', '')

    apk_files = glob.glob(os.path.join(apk_dir, "Aetherfin-v*.apk"))
    download_url = None
    if apk_files:
        apk_path = apk_files[0]
        print(f"Uploading {apk_path} to 0x0.st...")
        download_url = _upload_to_0x0(apk_path)

    title = "Release Successful!" if tag else "Build Successful!"
    icon = "\U0001f680" if tag else "\u2705"

    text = f"{icon} <b>Aetherfin {title}</b>\n"
    text += "\u2500" * 12 + "\n"
    if tag:
        text += f"<b>Tag:</b> <code>{tag}</code>\n"
    if download_url:
        text += f"<b>APK:</b> Direct download (no zip)\n"
    else:
        text += "<blockquote>Build completed, but upload failed.</blockquote>\n"
    text += "\u2500" * 12 + "\n"
    timestamp = os.environ.get('TG_TIMESTAMP', '')
    if timestamp:
        text += f"<i>{timestamp}</i>"

    buttons = []
    if download_url:
        buttons.append({"text": "\U0001f4e5 Download APK", "url": download_url})
    if run_url:
        buttons.append({"text": "\U0001f528 View Run", "url": run_url})
    if commit_url:
        buttons.append({"text": "\U0001f4bb Commit", "url": commit_url})

    reply_markup = {"inline_keyboard": [buttons]} if buttons else {}

    _send_text(text, reply_markup)


def fail_message():
    """Delete progress message, then send NEW fail message."""
    msg_id = os.environ.get('TG_MESSAGE_ID')

    # Delete the progress message first
    _delete_message(msg_id)

    tag = os.environ.get('TG_TAG', '')
    branch = os.environ.get('TG_BRANCH', 'unknown')
    build_id = os.environ.get('TG_BUILD_ID', 'unknown')
    actor = os.environ.get('TG_ACTOR', 'unknown')
    run_url = os.environ.get('TG_RUN_URL', '')

    # Build title based on whether it's a release or build
    title = "Release Failed!" if tag else "Build Failed!"
    icon = "\U0001f680" if tag else "\u274c"

    lines = [
        f"{icon} <b>Aetherfin {title}</b>",
        "\u2500" * 12,
    ]
    if tag:
        lines.append(f"<b>Tag:</b> <code>{tag}</code>")
    lines.extend([
        f"<b>Branch:</b> <code>{branch}</code>",
        f"<b>Build ID:</b> <code>{build_id}</code>",
        f"<b>Triggered by:</b> <code>{actor}</code>",
        "\u2500" * 12,
        "<blockquote>Check the error log for details.</blockquote>",
    ])
    text = "\n".join(lines)

    buttons = []
    if run_url:
        buttons.append({"text": "\U0001f6a7 View Error Log", "url": run_url})

    reply_markup = {"inline_keyboard": [buttons]} if buttons else {}

    _send_text(text, reply_markup)


def main():
    if len(sys.argv) < 2:
        print("Usage: python tool/telegram_notifier.py <init|update|success|fail>")
        sys.exit(1)

    action = sys.argv[1]
    if action == 'init':
        init_message()
    elif action == 'update':
        update_message()
    elif action == 'success':
        success_message()
    elif action == 'fail':
        fail_message()
    else:
        print(f"Unknown action: {action}")
        sys.exit(1)


if __name__ == '__main__':
    main()
