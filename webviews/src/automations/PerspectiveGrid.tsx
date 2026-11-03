import { useEffect, useRef } from "react";

const PULSE_COLORS = ["#60a5fa", "#a78bfa", "#f472b6", "#fbbf24", "#34d399", "#22d3ee"];
const LINES = 44;
const PULSES = 16;

/** Animation speed: x1 while the assistant works, x0.3 while idle, 0 when static. */
export function gridSpeed(busy: boolean, reduceMotion: boolean): number {
  if (reduceMotion) return 0;
  return busy ? 1 : 0.3;
}

type Pulse = { line: number; t: number; v: number; col: string };

/** Perspective grid with coloured light pulses (vanishing point at 52 % height). */
export function PerspectiveGrid({ busy, reduceMotion }: { busy: boolean; reduceMotion: boolean }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const speedRef = useRef(gridSpeed(busy, reduceMotion));
  speedRef.current = gridSpeed(busy, reduceMotion);
  const reducedRef = useRef(reduceMotion);
  reducedRef.current = reduceMotion;

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const isStatic = () => reducedRef.current || media.matches;
    const pulses: Pulse[] = Array.from({ length: PULSES }, (_, i) => ({
      line: Math.floor(Math.random() * LINES),
      t: Math.random(),
      v: 0.002 + Math.random() * 0.004,
      col: PULSE_COLORS[i % PULSE_COLORS.length] ?? "#60a5fa",
    }));
    const horizontals = Array.from({ length: 12 }, (_, i) => i / 12);
    let width = 0;
    let height = 0;
    let frameId = 0;

    const lineColor = () =>
      getComputedStyle(canvas).getPropertyValue("--au-grid-line").trim() || "255,255,255";

    const resize = () => {
      const ratio = window.devicePixelRatio || 1;
      width = canvas.width = Math.max(1, Math.round(canvas.clientWidth * ratio));
      height = canvas.height = Math.max(1, Math.round(canvas.clientHeight * ratio));
      if (isStatic()) draw(0);
    };

    const draw = (speed: number) => {
      const ratio = window.devicePixelRatio || 1;
      const rgb = lineColor();
      ctx.clearRect(0, 0, width, height);
      const vx = width / 2;
      const vy = height * 0.52;
      const base = height * 1.02;
      ctx.lineWidth = ratio;
      for (let i = 0; i < LINES; i++) {
        const bx = (i / (LINES - 1)) * width * 3 - width;
        ctx.strokeStyle = `rgba(${rgb},.07)`;
        ctx.beginPath();
        ctx.moveTo(vx, vy);
        ctx.lineTo(bx, base);
        ctx.stroke();
      }
      for (let k = 0; k < horizontals.length; k++) {
        horizontals[k] = ((horizontals[k] ?? 0) + 0.0015 * speed) % 1;
        const p = (horizontals[k] ?? 0) ** 2;
        const y = vy + (base - vy) * p;
        ctx.strokeStyle = `rgba(${rgb},${0.04 + p * 0.07})`;
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(width, y);
        ctx.stroke();
      }
      ctx.lineWidth = 2 * ratio;
      for (const p of pulses) {
        p.t += p.v * speed;
        if (p.t > 1) {
          p.t = 0;
          p.line = Math.floor(Math.random() * LINES);
        }
        const bx = (p.line / (LINES - 1)) * width * 3 - width;
        const e = p.t * p.t;
        const e0 = Math.max(0, p.t - 0.18) ** 2;
        const x1 = vx + (bx - vx) * e;
        const y1 = vy + (base - vy) * e;
        const x0 = vx + (bx - vx) * e0;
        const y0 = vy + (base - vy) * e0;
        const g = ctx.createLinearGradient(x0, y0, x1, y1);
        g.addColorStop(0, "transparent");
        g.addColorStop(1, p.col);
        ctx.strokeStyle = g;
        ctx.globalAlpha = 0.9;
        ctx.beginPath();
        ctx.moveTo(x0, y0);
        ctx.lineTo(x1, y1);
        ctx.stroke();
        ctx.globalAlpha = 1;
      }
    };

    const frame = () => {
      if (isStatic()) {
        draw(0);
        return;
      }
      draw(speedRef.current);
      frameId = requestAnimationFrame(frame);
    };

    const restart = () => {
      cancelAnimationFrame(frameId);
      resize();
      frame();
    };
    // Static pulses sit at fixed, spread-out positions instead of random ones.
    pulses.forEach((p, i) => {
      p.t = 0.15 + ((i * 0.37) % 0.8);
    });
    const observer = new ResizeObserver(restart);
    observer.observe(canvas);
    media.addEventListener("change", restart);
    restart();
    return () => {
      cancelAnimationFrame(frameId);
      observer.disconnect();
      media.removeEventListener("change", restart);
    };
  }, [reduceMotion]);

  return <canvas ref={canvasRef} className="au-grid" aria-hidden="true" />;
}
