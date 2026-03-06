#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform float uGridSpacingX;
uniform float uGridSpacingY;
uniform float uStartX;
uniform float uStartY;
uniform float uLineWidth;
uniform vec4 uLineColor;
uniform float uIntersectionRadius;
uniform vec4 uIntersectionColor;
uniform vec4 uViewport;
uniform float uZoom;
uniform vec4 uBgColor;

out vec4 fragColor;

// Hash function for procedural noise
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Value noise with smooth interpolation
float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion for layered paper texture
float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    for (int i = 0; i < 4; i++) {
        v += a * valueNoise(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// Antialiasing helper function
float smoothStep(float edge0, float edge1, float x) {
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// Line antialiasing function
float getLineAlpha(float dist, float lineWidth) {
    if (lineWidth <= 0.0) return 0.0;
    // Scale line width to screen pixels so it stays consistent across zoom levels
    float scaledWidth = lineWidth / uZoom;
    float halfWidth = scaledWidth * 0.5;
    float pixelRange = 1.0 / uZoom;

    return 1.0 - smoothStep(halfWidth - pixelRange, halfWidth + pixelRange, dist);
}

// Circle antialiasing function
float getCircleAlpha(float dist, float radius) {
    // Scale radius to screen pixels so it stays consistent across zoom levels
    float scaledRadius = radius / uZoom;
    float pixelRange = 1.0 / uZoom;
    return 1.0 - smoothStep(scaledRadius - pixelRange, scaledRadius + pixelRange, dist);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    float x = fragCoord.x;
    float y = fragCoord.y;

    float viewportLeft = uViewport.x;
    float viewportTop = uViewport.y;
    float viewportRight = uViewport.z;
    float viewportBottom = uViewport.w;

    // Discard fragments outside the viewport
    if (x < viewportLeft || x > viewportRight || y < viewportTop || y > viewportBottom) {
        fragColor = vec4(0.0);
        return;
    }

    // Subtle paper texture — fixed in screen space so it doesn't swim when panning
    vec2 screenPos = fragCoord * uZoom;
    float grain = fbm(screenPos * 0.8) * 0.5 + fbm(screenPos * 2.4) * 0.25;
    float paperVariation = (grain - 0.375) * 0.04; // very subtle ±2% brightness variation
    vec4 paper = vec4(uBgColor.rgb + paperVariation, uBgColor.a);

    float verticalAlpha = 0.0;
    float horizontalAlpha = 0.0;
    float intersectionAlpha = 0.0;

    // Calculate vertical line alpha
    if (uGridSpacingX > 0.0) {
        float xSteps = round((x - uStartX) / uGridSpacingX);
        float lineX = uStartX + xSteps * uGridSpacingX;
        if (lineX >= viewportLeft && lineX <= viewportRight) {
            float dx = abs(x - lineX);
            verticalAlpha = getLineAlpha(dx, uLineWidth);
        }
    }

    // Calculate horizontal line alpha
    if (uGridSpacingY > 0.0) {
        float ySteps = round((y - uStartY) / uGridSpacingY);
        float lineY = uStartY + ySteps * uGridSpacingY;
        if (lineY >= viewportTop && lineY <= viewportBottom) {
            float dy = abs(y - lineY);
            horizontalAlpha = getLineAlpha(dy, uLineWidth);
        }
    }

    // Calculate intersection alpha
    if (uIntersectionRadius > 0.0 && uGridSpacingX > 0.0 && uGridSpacingY > 0.0) {
        float xSteps = round((x - uStartX) / uGridSpacingX);
        float ySteps = round((y - uStartY) / uGridSpacingY);
        vec2 intersection = vec2(
            uStartX + xSteps * uGridSpacingX,
            uStartY + ySteps * uGridSpacingY
        );
        
        if (intersection.x >= viewportLeft && intersection.x <= viewportRight &&
            intersection.y >= viewportTop && intersection.y <= viewportBottom) {
            float dist = distance(fragCoord, intersection);
            intersectionAlpha = getCircleAlpha(dist, uIntersectionRadius);
        }
    }

    // Blend grid elements on top of paper
    vec4 lineColorWithAlpha = uLineColor * max(verticalAlpha, horizontalAlpha);
    vec4 intersectionColorWithAlpha = uIntersectionColor * intersectionAlpha;
    vec4 gridColor = mix(lineColorWithAlpha, intersectionColorWithAlpha, intersectionAlpha);

    // Composite: paper background + grid overlay
    fragColor = vec4(mix(paper.rgb, gridColor.rgb, gridColor.a), paper.a);
}