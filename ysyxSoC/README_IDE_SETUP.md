# IDE Setup for ysyxSoC (Scala/Chisel)

To enable code navigation (Jump to Definition, etc.) in VS Code:

1.  **Install Extension**: Install the **Scala (Metals)** extension from the VS Code Marketplace.
    *   ID: `scalameta.metals`

2.  **Import Build**:
    *   I have already generated the BSP configuration for you by running `./mill -i mill.bsp.BSP/install`.
    *   When you open this folder, Metals should detect it.
    *   If not, open the Command Palette (`Ctrl+Shift+P`) and run **"Metals: Import Build"**.

3.  **Workspace Structure**:
    *   Since this project is in a subdirectory (`ysyxSoC`), Metals works best if you open this folder directly: `File -> Open Folder... -> /home/hy258/ysyx-workbench/ysyxSoC`.
    *   Alternatively, if you keep the root workspace open, ensure Metals is enabled for this workspace.

## Troubleshooting
If you see "Metals is not enabled", try clicking the Metals icon in the Activity Bar or running "Metals: Start Server".
