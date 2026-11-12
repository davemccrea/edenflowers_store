import confetti from "../vendor/canvas-confetti.mjs";

// Each prize is picked at random from this list, so the repeat makes 🥇 twice
// as common as the others.
const prizes = ["🥇", "🥇", "🏅", "😍"].map((text) =>
  confetti.shapeFromText({ text, scalar: 3 }),
);

// Confetti bursts from the bottom corners, then prizes rain down.
export function celebrateFulfilled() {
  confetti({
    particleCount: 80,
    angle: 60,
    spread: 60,
    origin: { x: 0, y: 1 },
  });
  confetti({
    particleCount: 80,
    angle: 120,
    spread: 60,
    origin: { x: 1, y: 1 },
  });

  // Each prize starts at its own height above the page, so they arrive after
  // the bursts and fall as a shower rather than a single row.
  for (let i = 0; i < 45; i++) {
    confetti({
      particleCount: 1,
      angle: 270,
      spread: 100,
      startVelocity: 15,
      gravity: 1.2,
      ticks: 600,
      origin: { x: Math.random(), y: -Math.random() },
      shapes: prizes,
      scalar: 3,
      flat: true,
    });
  }
}
