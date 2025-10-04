#!/bin/bash

# Build script for Bitcoin Silver Web Wallet

echo "Installing dependencies..."
flutter pub get

echo "Building for web..."
flutter build web --release --base-href "/web-wallet/"

echo "Build complete! Output is in build/web/"
echo ""
echo "To deploy to GitHub Pages:"
echo "1. cd build/web"
echo "2. git init"
echo "3. git add ."
echo "4. git commit -m 'Deploy web wallet'"
echo "5. git branch -M gh-pages"
echo "6. git remote add origin https://github.com/YOUR_USERNAME/web-wallet.git"
echo "7. git push -u origin gh-pages"
