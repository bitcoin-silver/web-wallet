# Deployment Guide - Bitcoin Silver Web Wallet

## Quick Deploy to GitHub Pages

### Method 1: Automated with GitHub Actions (Recommended)

1. **Push your code to GitHub**:
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/web-wallet.git
   git push -u origin main
   ```

2. **GitHub Actions will automatically**:
   - Build the Flutter web app
   - Deploy to `gh-pages` branch
   - Your wallet will be live at `https://YOUR_USERNAME.github.io/web-wallet/`

3. **Enable GitHub Pages** (first time only):
   - Go to repository Settings → Pages
   - Source: Deploy from branch
   - Branch: `gh-pages` / `root`
   - Save

### Method 2: Manual Build and Deploy

1. **Build the web app**:
   ```bash
   chmod +x build.sh
   ./build.sh
   ```

   Or manually:
   ```bash
   flutter pub get
   flutter build web --release --base-href "/web-wallet/"
   ```

2. **Deploy to GitHub Pages**:
   ```bash
   cd build/web
   git init
   git add .
   git commit -m "Deploy web wallet"
   git branch -M gh-pages
   git remote add origin https://github.com/YOUR_USERNAME/web-wallet.git
   git push -u origin gh-pages -f
   ```

3. **Enable GitHub Pages**:
   - Go to repository Settings → Pages
   - Source: Deploy from branch
   - Branch: `gh-pages` / `root`
   - Save

4. **Access your wallet**:
   - URL: `https://YOUR_USERNAME.github.io/web-wallet/`

### Method 3: Deploy from docs/ folder

1. **Build to docs folder**:
   ```bash
   flutter build web --release --base-href "/web-wallet/"
   rm -rf docs
   cp -r build/web docs
   ```

2. **Push to GitHub**:
   ```bash
   git add docs
   git commit -m "Deploy to GitHub Pages"
   git push
   ```

3. **Enable GitHub Pages**:
   - Settings → Pages
   - Source: Deploy from branch
   - Branch: `main` / `docs`
   - Save

## Updating the Deployment

When you make changes:

### With GitHub Actions:
```bash
git add .
git commit -m "Update wallet"
git push
# GitHub Actions will rebuild and deploy automatically
```

### Manual:
```bash
flutter build web --release --base-href "/web-wallet/"
cd build/web
git add .
git commit -m "Update"
git push
```

## Important Notes

1. **Base href**: Update `--base-href` to match your repository name:
   - Repository: `web-wallet` → `--base-href "/web-wallet/"`
   - Repository: `btcs-wallet` → `--base-href "/btcs-wallet/"`
   - Custom domain: Use `--base-href "/"`

2. **GitHub Actions workflow**: Edit `.github/workflows/deploy.yml` and update:
   ```yaml
   run: flutter build web --release --base-href "/YOUR-REPO-NAME/"
   ```

3. **Custom domain** (optional):
   - Add CNAME file to `web/` folder with your domain
   - Configure DNS settings
   - Update workflow with `cname: yourdomain.com`

## Testing Locally

Before deploying, test locally:

```bash
flutter run -d chrome
```

Or serve the built files:

```bash
flutter build web --release
cd build/web
python3 -m http.server 8000
# Open http://localhost:8000
```

## Troubleshooting

**404 errors**: Check base-href matches repository name

**Assets not loading**: Verify base-href is correct in build command

**GitHub Pages not updating**: Clear browser cache, check gh-pages branch has new commit

**CORS errors with RPC**: RPC server must allow cross-origin requests from your GitHub Pages URL
