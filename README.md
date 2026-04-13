# Face Analysis and Style Guide (Work in Progress)

## Overview
This project is a mobile application that analyzes facial images to determine face shape and provide personalized hairstyle and eyeglass recommendations.

## Features
- Face shape classification using rule based geometric analysis
- Personalized style recommendations
- Mobile interface built with Flutter

## Current Status
Work in progress – currently improving calibration for more accurate face shape detection.

## Tech Stack
- Flutter
- Dart

## How It Works
The application analyzes facial proportions using rule based geometric calculations. Key measurements such as face length, jaw width, and forehead width are compared to determine the face shape.

These proportions are mapped to predefined categories such as oval, round, and square. Based on the detected face shape, the system generates personalized hairstyle and eyeglass recommendations.

## Challenges
- Calibrating face shape detection for different face proportions
- Ensuring consistent classification across varying image inputs
- Defining effective thresholds for rule based classification

## Future Improvements
- Improve classification accuracy through better calibration
- Transition from rule based system to machine learning approach
- Add real time face detection using camera input

## Author
Mustafa Şahin
