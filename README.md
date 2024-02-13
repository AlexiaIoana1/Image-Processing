# Image Processing

**Project Overview**

This Verilog project implements image mirroring, grayscale conversion, and image sharpening using a Finite State Machine (FSM) to manage the sequential execution of these operations. The system is optimized to work within hardware constraints, including a limited cache for image data.

**Key Features**

- **Transformation Pipeline:** Employs a 3-stage FSM to apply mirroring, grayscale,and sharpness in order. This ensures consistent completion of each stage prior to the next.
- **Hardware Efficiency:** Leverages a strategic 6-line caching system to enable the sharpening filter implementation despite memory limitations.
- **Image Format:** Designed for operation on 64x64 image matrices.

**How it Works**

1. **Mirroring:**
    
    - Reads image columns sequentially.
    - Writes mirrored pixels based on their position within the column.
2. **Grayscale Conversion:**
    
    - Processes the image pixel-by-pixel (top-to-bottom, left-to-right).
    - Calculates grayscale value for each pixel using the formula:  `PixelGrayscale = [max(R,G,B) + min(R,G,B)] / 2`
3. **Sharpness Filter**
    
    - Maintains a cache of the last 3 image lines read.
    - Applies a convolution-based sharpness filter, updating the cache lines to calculate results for subsequent image rows.
    

**Finite State Machine (FSM)**

The FSM governs transitions between image processing stages and manages the constrained cache system. States for reading, writing, and calculation are carefully sequenced to ensure correctness and optimal use of resources.

**Hardware Considerations**

- **Cache Strategy:** The 6-line cache (3 for data, 3 for manipulation) is key to enabling the sharpness calculation within memory constraints.
- **Sequential Operations:** Because of the cache limits, operations must be applied fully to the image in stages - there's no 'all-at-once' calculation per pixel.

**Project Scope**

This project demonstrates the power of Verilog and FSM architectures for hardware-based image manipulation.

**To Run** (If applicable, include simulation/synthesis instructions)

**Challenges and Learning**

- **Memory Management:** Implementing the sharpening filter within a limited cache was a core challenge, emphasizing resource optimization in hardware design.
- **FSM Complexity:** Designing the FSM states and transitions to balance correctness and optimization provided a deep understanding of sequential logic principles.
