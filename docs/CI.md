# CI/CD Documentation

This document describes the Continuous Integration and Continuous Deployment workflows for `@avify-com/expo-opus`.

## Overview

The project uses GitHub Actions for automated testing, building, and publishing. There are two main workflows:

| Workflow | File | Purpose |
|----------|------|---------|
| **CI** | `.github/workflows/ci.yml` | Runs on every push/PR to validate code |
| **Publish** | `.github/workflows/publish.yml` | Publishes package to GitHub Packages |

---

## CI Workflow (`ci.yml`)

**Triggers:**
- Push to `master` branch
- Pull requests targeting `master`

### Jobs

#### 1. `build-typescript`
Runs on: `ubuntu-latest`

Validates the TypeScript build and runs tests:
- Installs Node.js 20 with npm caching
- Runs `npm ci` to install dependencies
- Builds TypeScript with `npm run build`
- Runs tests with `npm test`
- Verifies `build/index.js` and `build/index.d.ts` exist

#### 2. `build-android-native`
Runs on: `ubuntu-latest`

Builds native Android libraries from source:
- Sets up Android NDK 26.1.10909125
- Runs `scripts/build-opus-android.sh` to build libopus
- Runs `scripts/build-lame-android.sh` to build LAME encoder
- Verifies static libraries exist for all ABIs:
  - `arm64-v8a`
  - `armeabi-v7a`
  - `x86`
  - `x86_64`
- Uploads artifacts with 90-day retention

#### 3. `build-ios-native`
Runs on: `macos-latest`

Builds native iOS frameworks from source:
- Sets up latest stable Xcode
- Runs `scripts/build-opus-ios.sh` to build libopus and libogg
- Verifies xcframeworks exist:
  - `ios/Frameworks/libopus.xcframework`
  - `ios/Frameworks/libogg.xcframework`
- Uploads artifacts with 90-day retention

---

## Publish Workflow (`publish.yml`)

**Triggers:**
- GitHub Release published
- Manual dispatch (workflow_dispatch) with optional version input

### Jobs

#### 1. `build-android-native`
Same as CI workflow - builds Android native libraries.

#### 2. `build-ios-native`
Same as CI workflow - builds iOS frameworks and shims.

#### 3. `test`
Runs on: `ubuntu-latest`  
**Depends on:** `build-android-native`, `build-ios-native`

- Downloads native artifacts from previous jobs
- Runs TypeScript tests to ensure everything works together

#### 4. `publish`
Runs on: `ubuntu-latest`  
**Depends on:** `build-android-native`, `build-ios-native`, `test`

Publishes the package to GitHub Packages:
- Downloads all native artifacts
- Verifies all native libraries are present
- Builds TypeScript
- Validates version matches release tag (on release trigger)
- Publishes to `https://npm.pkg.github.com` under `@avify-com` scope

---

## Creating a Release

### Step 1: Update Version

Update the version in `package.json`:

```bash
npm version patch  # or minor, major
```

This will:
- Update `package.json` version
- Create a git commit
- Create a git tag (e.g., `v1.0.1`)

### Step 2: Push Changes

```bash
git push origin master --tags
```

### Step 3: Create GitHub Release

1. Go to **Releases** → **Draft a new release**
2. Select the tag you just created (e.g., `v1.0.1`)
3. Set release title (e.g., `v1.0.1`)
4. Add release notes describing changes
5. Click **Publish release**

The publish workflow will automatically:
- Build all native libraries
- Run tests
- Validate version matches tag
- Publish to GitHub Packages

### Manual Publish (workflow_dispatch)

You can also trigger a publish manually:

1. Go to **Actions** → **Publish to GitHub Packages**
2. Click **Run workflow**
3. Optionally specify a version (leave empty to use `package.json` version)
4. Click **Run workflow**

---

## Artifacts

Both workflows produce artifacts that can be downloaded:

| Artifact | Contents | Retention |
|----------|----------|-----------|
| `android-native` | `jniLibs/` with static libraries for all ABIs | 90 days |
| `ios-frameworks` | `Frameworks/` with xcframeworks, `Shims/` with module maps | 90 days |

---

## Troubleshooting

### Build Failures

**TypeScript build fails:**
- Check for TypeScript errors in the build output
- Ensure all dependencies are properly declared in `package.json`

**Android native build fails:**
- Verify NDK version compatibility (currently using 26.1.10909125)
- Check `scripts/build-opus-android.sh` and `scripts/build-lame-android.sh` for errors

**iOS native build fails:**
- Verify Xcode version compatibility
- Check `scripts/build-opus-ios.sh` for errors

### Publish Failures

**Version mismatch error:**
- Ensure `package.json` version matches the release tag
- Tag should be `vX.Y.Z` format (e.g., `v1.0.0`)

**Authentication error:**
- The workflow uses `GITHUB_TOKEN` which is automatically provided
- Ensure the repository has `packages: write` permission

---

## Required Secrets

| Secret | Description | Auto-provided |
|--------|-------------|---------------|
| `GITHUB_TOKEN` | Used for publishing to GitHub Packages | ✅ Yes |

No additional secrets configuration is required.
