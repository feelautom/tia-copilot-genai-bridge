# T-IA Copilot Prompts

This document provides example prompts to use with your AI assistant (Claude, LobeChat, Cursor) connected to T-IA Connect.

## Project Discovery
- "Analyze my TIA Portal project and give me an overview of the hardware and software structure."
- "What are the available blocks in the 'Pumping_Station' folder?"
- "List all tags in the 'Default tag table' and check for potential address overlaps."

## Code Generation (SCL)
- "Generate a FB in SCL for a motor controller with Start/Stop logic and a thermal fault input."
- "Create a state machine for a conveyor system with 3 sensors: Load, Run, and Unload."
- "Write an OB1 call that scales an analog input (0-27648) to a REAL value (0.0-100.0)."

## Diagnostics & Optimization
- "Look at the 'FB_WaterPump' block and suggest how to optimize the thermal fault delay."
- "Verify if all used tags have comments and proper naming conventions."

## Simulation (PLCSim)
- "Start a PLCSim session for my PLC_1 and force the Start_Button tag to TRUE to test the sequence."
