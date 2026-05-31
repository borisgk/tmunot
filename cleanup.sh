#!/bin/bash

echo "Cleaning up photo directories..."
rm -rf photos/* 2>/dev/null || true

echo "Cleaning up databases..."
rm -rf databases/* 2>/dev/null || true

echo "Cleanup complete."
