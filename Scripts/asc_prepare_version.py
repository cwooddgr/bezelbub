#!/Users/cwood/projects/marketroid/.venv/bin/python
"""Prepare a Bezelbub App Store version on both platforms via the ASC API.

For each platform: find or create the App Store version, wait for the uploaded
build to finish processing, attach it, and set the en-US What's New. Optionally
(--submit) create a review submission for the version and submit it. Never
submits without --submit; every write is printed before it happens.

Usage:
  Scripts/asc_prepare_version.py --version 3.4.0 --macos-build 17 --ios-build 14 \
      --whats-new-file /path/to/whats-new.txt [--submit] [--dry-run]

Needs the marketroid venv (PyJWT) and the Admin key at
~/.appstoreconnect/private_keys/AuthKey_5WP4BBJK8R.p8 (same as the read-only
status script in overflight/tools/asc_release_status.py).
"""
import argparse, json, sys, time, urllib.error, urllib.parse, urllib.request

try:
    import jwt
except ImportError:
    sys.exit("PyJWT missing: run with /Users/cwood/projects/marketroid/.venv/bin/python")

KID = "5WP4BBJK8R"
ISS = "a602b5b5-5e74-4ab9-ac01-862715bdaab0"
KEY = f"/Users/cwood/.appstoreconnect/private_keys/AuthKey_{KID}.p8"
BASE = "https://api.appstoreconnect.apple.com"

ap = argparse.ArgumentParser()
ap.add_argument("--bundle-id", default="co.dgrlabs.bezelbub")
ap.add_argument("--version", required=True, help="marketing version, e.g. 3.4.0")
ap.add_argument("--macos-build", help="macOS build number to attach (omit to skip macOS)")
ap.add_argument("--ios-build", help="iOS build number to attach (omit to skip iOS)")
ap.add_argument("--whats-new-file", help="text file with the What's New for en-US")
ap.add_argument("--submit", action="store_true", help="also create + submit the review submission")
ap.add_argument("--dry-run", action="store_true", help="print writes without sending them")
ap.add_argument("--wait-minutes", type=int, default=30, help="how long to wait for build processing")
args = ap.parse_args()


def token():
    now = int(time.time())
    return jwt.encode({"iss": ISS, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                      open(KEY).read(), algorithm="ES256", headers={"kid": KID})


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token(),
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} -> HTTP {e.code}\n{e.read().decode()}")


def get(path):
    return call("GET", path)


def write(method, path, body):
    print(f"  {method} {path}\n    {json.dumps(body)}")
    if args.dry_run:
        print("    (dry run, not sent)")
        return {}
    return call(method, path, body)


apps = get("/v1/apps?filter[bundleId]=" + urllib.parse.quote(args.bundle_id))["data"]
if not apps:
    sys.exit(f"no app with bundle id {args.bundle_id}")
APP = apps[0]["id"]
print(f"{apps[0]['attributes']['name']} ({args.bundle_id}, ASC app {APP})")

whats_new = open(args.whats_new_file).read().strip() if args.whats_new_file else None
if whats_new and len(whats_new) > 4000:
    sys.exit("What's New exceeds 4000 characters")

plan = [(p, b) for p, b in (("MAC_OS", args.macos_build), ("IOS", args.ios_build)) if b]
if not plan:
    sys.exit("nothing to do: pass --macos-build and/or --ios-build")

for platform, build_number in plan:
    print(f"\n== {platform}: version {args.version}, build {build_number}")

    # 1. Find or create the App Store version.
    versions = get(f"/v1/apps/{APP}/appStoreVersions?filter[platform]={platform}"
                   f"&filter[versionString]={urllib.parse.quote(args.version)}")["data"]
    if versions:
        version = versions[0]
        print(f"  version exists: {version['id']} ({version['attributes']['appStoreState']})")
    else:
        # Copy the release type from the newest existing version on this platform
        # so the new one behaves like the last release.
        prev = get(f"/v1/apps/{APP}/appStoreVersions?filter[platform]={platform}&limit=1")["data"]
        release_type = prev[0]["attributes"].get("releaseType", "AFTER_APPROVAL") if prev else "AFTER_APPROVAL"
        version = write("POST", "/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": platform, "versionString": args.version,
                           "releaseType": release_type},
            "relationships": {"app": {"data": {"type": "apps", "id": APP}}},
        }}).get("data", {"id": "(dry-run)", "attributes": {}})
        print(f"  created version {version['id']} (releaseType {release_type})")
    vid = version["id"]

    # 2. Wait for the uploaded build to finish processing.
    deadline = time.time() + args.wait_minutes * 60
    build = None
    while True:
        builds = get(f"/v1/builds?filter[app]={APP}&filter[preReleaseVersion.platform]={platform}"
                     f"&filter[version]={build_number}&filter[preReleaseVersion.version]="
                     f"{urllib.parse.quote(args.version)}&fields[builds]=version,processingState,uploadedDate"
                     "&limit=5")["data"]
        if builds:
            build = builds[0]
            state = build["attributes"]["processingState"]
            print(f"  build {build_number}: {build['id']} {state}")
            if state == "VALID":
                break
            if state in ("FAILED", "INVALID"):
                sys.exit(f"  build {build_number} is {state}; not attaching")
        else:
            print(f"  build {build_number} not visible yet")
        if args.dry_run or time.time() > deadline:
            if not args.dry_run:
                sys.exit("  gave up waiting for build processing")
            break
        time.sleep(60)

    # 3. Attach the build.
    if build:
        write("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
              {"data": {"type": "builds", "id": build["id"]}})
        print("  build attached")

    # 4. What's New (en-US).
    if whats_new and vid != "(dry-run)":
        locs = get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
        loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
        if loc is None:
            sys.exit("  no en-US localization on this version")
        write("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}",
              {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                        "attributes": {"whatsNew": whats_new}}})
        print("  What's New set")

    # 5. Review submission (only on request).
    if args.submit and vid != "(dry-run)":
        rs = write("POST", "/v1/reviewSubmissions", {"data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": platform},
            "relationships": {"app": {"data": {"type": "apps", "id": APP}}},
        }}).get("data", {"id": "(dry-run)"})
        write("POST", "/v1/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": rs["id"]}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}},
            },
        }})
        write("PATCH", f"/v1/reviewSubmissions/{rs['id']}",
              {"data": {"type": "reviewSubmissions", "id": rs["id"], "attributes": {"submitted": True}}})
        print("  submitted for review")

print("\ndone")
