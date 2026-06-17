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


def _upload_to_gofile(file_path):
    try:
        server_resp = subprocess.run(
            ["curl", "-s", "https://api.gofile.io/servers"],
            capture_output=True,
            text=True,
            timeout=30
        )
        if server_resp.returncode != 0:
            print(f"Failed to get gofile server: {server_resp.stderr}")
            return None

        servers = json.loads(server_resp.stdout)
        if servers.get("status") != "ok" or not servers.get("data", {}).get("servers"):
            print("No gofile servers available")
            return None

        server = servers["data"]["servers"][0]["name"]

        result = subprocess.run(
            ["curl", "-s", "-F", f"file=@{file_path}", f"https://{server}.gofile.io/contents/uploadfile"],
            capture_output=True,
            text=True,
            timeout=300
        )
        if result.returncode != 0:
            print(f"curl failed: {result.stderr}")
            return None

        resp = json.loads(result.stdout)
        if resp.get("status") == "ok":
            url = resp["data"]["downloadPage"]
            print(f"  Uploaded {os.path.basename(file_path)}: {url}")
            return url
        else:
            print(f"gofile error: {resp}")
            return None
    except subprocess.TimeoutExpired:
        print("Upload to gofile timed out")
        return None
    except Exception as e:
        print(f"Error uploading to gofile: {e}")
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
    _delete_message(msg_id)

    tag = os.environ.get('TG_TAG', '')
    apk_dir = os.environ.get('TG_APK_DIR', 'build/app/outputs/flutter-apk')
    run_url = os.environ.get('TG_RUN_URL', '')
    commit_url = os.environ.get('TG_COMMIT_URL', '')
    mode = os.environ.get('TG_MODE', 'release')
    branch = os.environ.get('TG_BRANCH', 'unknown')
    build_id = os.environ.get('TG_BUILD_ID', 'unknown')
    actor = os.environ.get('TG_ACTOR', 'unknown')
    sha = os.environ.get('TG_SHA', '')
    commit = os.environ.get('TG_COMMIT', '')
    timestamp = os.environ.get('TG_TIMESTAMP', '')
    build_duration = os.environ.get('TG_BUILD_DURATION', '')
    smart_skipped = os.environ.get('TG_SMART_SKIPPED', '')

    apk_files = sorted(glob.glob(os.path.join(apk_dir, "Aetherfin-v*arm64*.apk")))
    apk_name = None
    apk_size = None
    download_url = None
    if apk_files:
        apk_path = apk_files[0]
        apk_name = os.path.basename(apk_path)
        apk_size = os.path.getsize(apk_path)
        print(f"Uploading {apk_name} to gofile...")
        download_url = _upload_to_gofile(apk_path)

    icon = "\U0001f680" if tag else "\u2705"
    status = "Release Successful!" if tag else "Build Successful!"

    lines = [f"{icon} <b>Aetherfin {status}</b>", ""]

    if build_duration:
        duration_s = int(build_duration) // 1000
        mins = duration_s // 60
        secs = duration_s % 60
        lines.append(f"\u23f1 <b>Total:</b> {mins}m {secs}s")
        lines.append("")

    # APK info
    if apk_name:
        lines.append(f"<b>App:</b> <code>{apk_name}</code>")
    if apk_size:
        size_mb = apk_size / (1024 * 1024)
        lines.append(f"<b>Size:</b> {size_mb:.1f}MB")
    lines.append(f"<b>Mode:</b> <code>{mode}</code>")
    lines.append("")

    lines.append(f"<b>Branch:</b> <code>{branch}</code>")
    lines.append(f"<b>Build ID:</b> <code>{build_id}</code>")
    lines.append(f"<b>Triggered by:</b> <code>{actor}</code>")
    if sha and commit:
        lines.append("")
        lines.append(f"<b>Last Commit:</b>")
        lines.append(f"<code>{sha}</code> \u2014 {commit}")
    lines.append("\u2500" * 12)

    if smart_skipped:
        lines.append(f"\u23ed <b>Skipped:</b> <code>{smart_skipped.strip()}</code>")
        lines.append("")

    if timestamp:
        lines.append(f"<i>{timestamp}</i>")

    text = "\n".join(lines)

    buttons = []
    if download_url:
        buttons.append([{"text": "\U0001f4e5 Download APK", "url": download_url}])
    if run_url:
        buttons.append([{"text": "\U0001f528 View Run", "url": run_url}])
    if commit_url:
        buttons.append([{"text": "\U0001f4bb Commit", "url": commit_url}])

    reply_markup = {"inline_keyboard": buttons} if buttons else {}
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
