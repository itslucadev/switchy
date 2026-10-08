#!/bin/bash

xcodebuild \
  -project switchy.xcodeproj \
  -scheme Debug \
  -configuration Debug \
  -derivedDataPath DerivedData
