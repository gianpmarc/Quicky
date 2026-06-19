# Contributing

Thanks for helping make Quicky better.

## Local Development

1. Install the Xcode command line tools.
2. Run `./script/build_and_run.sh`.
3. Keep pull requests focused on one workflow or platform service at a time.

## Code Style

- Prefer small Swift files named after their primary type.
- Keep SwiftUI views declarative and move AppKit-specific behavior into
  `Services` or narrow representables/controllers.
- Do not include proprietary screenshots, icons, names, or behavior copied from
  closed-source capture tools.

## Testing Checklist

- Build with `swift build`.
- Launch with `./script/build_and_run.sh --verify`.
- Test full-screen screenshot, area screenshot, and area recording.
- Verify the output files appear in `~/Pictures/Quicky/Media`.
