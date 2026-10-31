// Service worker for the installed admin app, registered with scope /admin.
// It shows new-order notifications, keeps the app icon's badge in step, and
// covers the app's launch with a loading screen. Nothing is cached: LiveView
// needs its socket anyway.

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) =>
  event.waitUntil(self.clients.claim()),
);

// Opening the app (or iOS reloading it after evicting it) shows a blank screen
// until the server's first byte arrives. Answering that launch at once with
// this page, which then asks for the real one, keeps it on screen instead:
// the browser holds the old page until the new one paints. The logo must not
// animate in: once the page asks for the real one, Safari stops running its
// animations, so a faded-in logo never appears.
const launchScreen = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#BDCCC3">
<title>Eden Admin</title>
<style>
  html, body { height: 100%; margin: 0; background: oklch(99% 0.004 75); }
  body { display: grid; place-items: center; }
  svg { width: 160px; }
</style>
</head>
<body>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 207.87466 207.87466" role="img" aria-label="Eden Flowers"><path d="m0 0-1.5-.2q-1.3 0-2.1-.4l-.6-.2a23 23 0 0 1-7-3.6l-2.4-1.5-.8-.5-1.7-1-.6-.3-1-.6 1.5 1.6a53 53 0 0 1 4.6 6.3 16 16 0 0 1 2.4 6.2c1.3 0 2.7 1.4 3.4 2.6q.8 1.3 1.2 2.8.3 1.1 1 2.3v.6H-4l-1.6-.8-1-.6a7 7 0 0 1-2-1.7A7 7 0 0 1-10 8q0-.8.3-1.7V6c-.3-2.5-1.6-4.7-2.8-7l-.1-.1-1.3-2 .2.9q.6 2.2.6 4.7c0 2.7.4 5.8 1.6 8.2l.7 1.3.4 1-.9-.9-1.5-2-1-1.4q-1.7-2-2.3-4.3-.7-2.7-.2-5l.2-.6q.3-.9.4-1.9v-.5q.1-1.2-.4-2.1l-1.4-1.7-1.6-1.3-1.2-.9q-1.3-1.2-2.8-2l-.7-.5-2.2-1.3-1-.4-1.7-.7q-2.8-1.5-6-2.2s3 1.3 4 2.2l2.3 2.2q1.3 1.7 2.4 4l3.7 7.4 2.3 3.5 1.5 1.9-.7-.2q-2.1-.7-4.4-3.8A61 61 0 0 1-28-5.6L-29.8-8l-3-4-2.4-3.3q-.9-1.2-2.1-1.9l-.6-.1-4.6-.6-1.7-.1q-2.9-.2-5.6.1l2.6.9q2.2.7 4.4 2.1 2.9 2.2 4.7 4.6l1.6 1.8.5.5.3.4q.9 1 2 1.6l.9.7h-.8a14 14 0 0 1-4.6-1.3l-.6-.3q-2.5-1.3-4.3-3.3l-.8-.6-2-2q-1-1.2-2.2-2.2l-.2-.2q-1.7-1.7-3.8-2.3h-.1l-1.1.1-1 .2-1.3.1s-.7 0-.7-.3v-.1h.1l3-.5 1.3-.1h.3q1.3-.3 3-.4l1-.2h.6l.8-.4.9-.3 1.1-1 1-1 .8-.5q.7-.7 1.6-1.2a17 17 0 0 1 8-1.9l3.5.2h1.4l1.4.2-2.2.9-3 1.4-.3.2a31 31 0 0 1-4.6 1.9q-2 .9-5.3 1.3l-.4.1-1.4.2 4.5.4 1.8.3c1 .1 3.7 1 4.1 1q.9.2 1.6.6l.6.2 2-1 .5-.3q1-.5 2.2-.8l.4-.1q2.6-.5 5.6.1 1.8.5 3.5 1.2l2.3 1 1 .3 2.7.8 1 .2 2 .7-.7.3a22 22 0 0 1-11-1.2l-1-.3q-1.2-.5-2.5-.6H-26l-1.3.2-1.6.2h-.9q.6 0 1.2.4l1 .4 2.6 1.2 3 1.9.3.2 2.8 2A13 13 0 0 1-8-5.4q2 1.9 4 3.3 1.5 1 3 1.4L.8 0z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 172.6 159.4)"/><path d="M0 0q-.3.7 0 1.5l.5.2 1.1.5q.5.3.9.9L2 1.9v-.1l-.2-.3v-.3h.3Q2.8 2 3 3v.2-.8l-.1-.8.2-.2.2.2.1.3.1.5v.5l.2-.2C4 2.1 4.6 1 3.4.1c-.6-.5-2-.7-2.8-.5Q.2-.4 0 0m-3.5 3.7h.3c-.3-.5-.6-1.3 0-2q1.2-1 2.6-.5V.5L-1 .3-2 0q-1.2-.2-2 .8l-.2.2q-.7.8-.3 2 0 .6 1 .8M-.3 2q-.8-.4-2-.1-.4 0-.6.6t.2 1.3l2.2.2-.1-.2.1-.2q1 0 1.8.4h.1l.7.3L2 4q-.6-.5-1.2-.7A.2.2 0 0 1 .5 3l.3-.2.7.4h.2l.5.5-.2-.4q-.7-1-2-1.2zm.5 8.5q.5.4.9.2c.6-.2 1.1-1.1 1.3-1.9l.3-1.1.2-1.1V6v.4q-.2 1-.7 1.7H2q-.2 0-.1-.2l.2-.6.1-.4Q2 7.6 1.3 8h-.2v-.2q0-.4.4-.7l.5-1-.6.7-.2.3a12 12 0 0 1-2.6 2h-.1c0 .4.9.8 1.3 1zm-5.3-3C-4.5 8.2-4 9-2.8 9q1.3-.2 2.2-1.1l.5-.4 1-1q-.7 1-1.8 1h-.2v-.3a5 5 0 0 0 2-1.3l.5-.5.2-.1H1l-1 .2-2 .5-.3-.1.1-.3q1.5-.8 3.2-.8h.3-.2l-2.3-.5q-1.3-.2-2.6 0h-.1c-.7 0-1.4.7-1.7 1.2q-.3.6.4 1.7zM-7 28v-.5l-.1-1-.1.2-.2.1q-.2 0-.2-.2L-8 25l-.1.4-.2.2-.1.6q0 .5-.2.9h-.2L-9 27l.2-1.2-.4.6-.3.7h-.2l-.2-.2q.4-1.1 1.2-2l-.5.2-.6.2q-1.2.4-2 1.3l-.8.6h-.2l-1 .7.2 1.2q.5 1 1.4 1.1h1.6q.8-.1 1.4.2.8.4 1.3.2c.6-.4.7-1.7.7-2.5m5.3-3.4q-.4-.8-1.2-1l-.3-.2q-1-.6-2-.4h-.2a3 3 0 0 1 2 .6q.3.1.1.2 0 .2-.2.1l-1.7-.2q.7 0 1.2.6v.2l-.2.1-1.2-.4q1.4.9 2 2.4.3 0 .5-.3l.4-.2q1-.6.8-1.5m-4 5 .6.3.4.1q.6.3 1 0c.2-.3.4-1 0-3q-.3-1-1-1.6l.2.8-.2.2H-5l-.1-.3q-.3-.7-1-1.3l-.3-.1.2.1q.6.7.9 1.8a.2.2 0 0 1-.2.3l-.2-.1-.3-.7-.5-.8-.5-.5v.2l.1.5.1.6q.3.4.3 1v2.1l-.1.4h.8m-11-3.7q.1.4.6.6l.4.3.1.1q.6.8 1.5.6l.4-.3.3-.1 1.2-1 .7-.5q.7-.6 1.6-.9l-.6.2h-.3v-.4q.4 0 .6-.3h-.1l-1.5.4-.2-.1v-.2q.5-.4 1.2-.5h-2.3q-1 .1-2 .5l-1.3 1zm2.3-4.2.3.9-.3.6-.2.3.6-.1a17 17 0 0 1 4.5 0l-1-.1-.2-.2.1-.2q1.2-.2 2.1.3h.1q-1.4-.9-3.2-1.1l-.2-.2.2-.2c.6 0 1.8.2 2.8.7q-.2-.5-.6-.8a4 4 0 0 0-2.5-1.4c-.8-.2-2.2 0-2.6.6q-.3.4 0 .9m23.1-5.9-.2.4q0 .5.2.8.3.6.8.8.1-.9.4-1.4-.7 0-1.2-.6m7.9-1.5.4.4q.4.2.5.6.4.8.2 1.8l-.2.1-.2-.1q0-1.2-.5-2l-.3-.2v2q0 .8-.2 1.4l1-.1.4-.2q.7-.4.5-1.2v-.3q-.3-1.5-1.6-2.3m0 5.9q.6-.6.7-1.4L16 19l-1 1.5h.7l.7-.2M12 20q.8.5 1.5.5l1-.2c.4-.2.7-1 .9-1.5l.2-1.8v-2.3q0 .8-.3 1.4 0 .2-.2.1l-.2-.1q0-.6.2-1.1v-.4l-.2.3-.4.6-.6.8h-.2l-.1-.2q.2-.7.6-1.2L13 16l-.1.2h-.2q-.2 0-.1-.2.4-.8 1.2-1.4l.5-.3a6 6 0 0 0-3.8 2q-1 1.3-.6 3 .3.4 1 .4l1 .1zm-1.3-7.2q-1.2.3-2.2 1.4v.6q.2.7.9 1h.8a6 6 0 0 1 3.3-2l-.6.1-.2-.2.2-.2h.2-1.3l-.2-.2.1-.3h2l.8.1a7 7 0 0 0-3.8-.3m24.8-4h-.8l-.8-.3-.2-.1-1-.4c-.2.1-.5.9-.7 1.3l-.2.5q-.5.8-1.2 1.2l-1.8.9h-.2q-.5.3-1 .3l-1.5.3.4-.7c.6-.7 1.2-1 1.8-1.8q1.2-1.6 3.2-2.4l-1.7-.3h-.1l-3 .3h-.5l-.3.8v.3l-.3 1.4v.4q-.3 1.5-1 2.5c-1 1-1.8 1.6-3.5 1.6h-.6l.3-.5q.4-.6.6-1.3l.2-.6q.4-1.4 1.2-2.3c.2-.3 1-1.4 2-2a14 14 0 0 0-3.6.9q-1.4.6-2.3 1.4l-.4.3c-1 1-2.2 1.8-2.6 3.2q2.2.5 2.5 2.9v.2q.3.9-.1 1.5l-.7.4q-.1 1-.8 1.8-.5.4-1.2.4H15l-.2-.2q-.4.4-1 .4h-.1l-1-.1-.6-.4q-.6-.4-1.4-.4t-1.1-.4q-.4-.4-.3-1.5-.5-.2-.8-.6l-.1-.2-.5-.8q-.1-.6.4-1.3-.3-.8-.1-1.4t.8-1q1.6-.8 3.7-.8a5 5 0 0 1 3 1q.8-2 3.8-4h-.2l-2 .5q-1 .4-1.7.4-1 .1-1.7-.2l-.7-.3.6-.3 1.6-.7q1-.6 2-.8A6 6 0 0 1 20 8l.3.1h1.3q1.5-.7 4-.8 1.3 0 2.6-.3l-.7-.1a20 20 0 0 0-4-.5q-3.6 0-6.7.4a25 25 0 0 0-10.8 4L4.3 12Q2.5 13 1 14.3l-.4.4h.2q2.6 0 3.7 1.8.7 1.4.4 2.6l-.4 1.1-.2.4v1.9q0 .4-.2.5l-1-.7-.8-.9q-.4-.6-.5-1.4v-.4q-.2-.9-.9-1.6l-.6-1.2-.2-.3.1.3.2.7v1.8L-.4 21q-.4.7-1.1.8l-.4.1.2-1.8v-2.2q.1-.8.5-1.5v-.2a41 41 0 0 0-4.8 6l-.4.6 1.6-.4c.8 0 2 .5 2.7 1q1.3.9.5 2.4-.2.6-.8.7l-.2.1-.3.3-.3.2.1.5c.3 1 .2 2.4-.8 3q-.6.3-1.1 0l-.5-.2-.8-.2h-.5q-.3.4-.8.7-.8.3-1.8-.1-.8-.3-1.7-.2h-1.4q-1-.4-1.4-1.3l-.3-1.2-.8.1-.6-.3-.1-.2q-.2-.5-.8-.8l-.4-.3q-.4-.6-.2-1.2.4-1 2-1.7-.1-.4.4-1l.1-.3-.4-.5q-.4-.3-.4-.8.6-1.4 3-1.4a4 4 0 0 1 3 1q0 .3.3.4.5.3.8.9l.4.9.4.4.8-1 1-1.4.6-1.1q1-1.5 2.1-2.4l1-1a18 18 0 0 1-3.9 2.3q-1.5.6-3.2.3-.5 0-.7-.2l1-.5q1-.3 1.6-.7 1.3-1 2.2-1.3l1.2-.3q1.1-.1 1.9-.6l-.9.1q-1.7.4-3.7.2a17 17 0 0 1-4.6-1.3l-2.7-1.1.7-.3 1.3-.3.9-.2 1.5-.2h1.2l1.5-.2A8 8 0 0 1-2 13.6q.7.7 1.6 1h.2l.7-.6q1.5-1.6 3.2-2.5l2-1.2A28 28 0 0 1 10.2 8q1.6-.7 3.2-1l-1.1-.7-.4-.1q-1.2.2-2.2 1-1 .7-2.2 1Q6 8.4 4.9 8c-.2 0-.8-.2-1-.4 0 0 1.8-.7 2.5-1.2L8 5.5q1.3-.4 2.4 0l-1-.5q-1.7-.3-3.5-.3h-.4l-1.4.1-.6.1-.4.1.4.6q.2.8-.1 1.5l-.1.3-.2.7c-.3 1-.5 2.2-1.5 2.9-.7.5-1.3.1-1.8-.2l-.7-.4c-.3 0-1-.5-1.1-1q-1 .3-1.9 0-1.1-.6-1.6-1.7l-.3-.5q-.6-.8-.2-1.8.4-1.1 1.6-1.5l-.4-.4-.1-.4c-.3-.8-.5-1.2 0-2.1l.5-.6.3-.3q.6-.6 1.3-.7c.4-.1 1.7 0 2.2.5q.1-.6.7-.7.6-.3 1.2-.2 1.6 0 2.9 1c1 .9.3 2.5-.2 3.3l-.2.3-.5.9 2.3-.3 3.2.2 1.6.4q-.8-.7-1.3-1.7-.3-1-1-1.3L7 1.2q-.4-.3-.5-1l.4.2 1.5.6q1 .3 2 1 .7.8 1 1.7l.2.2.1 1 .1.6.7.3q.3 0 .5.3.3 0 .5.3l.6.4.8-.2 2-.4q1-.3 2-.2l1.3-.1 2.7-.1-1.2-.2-1.6-.2Q18.7 5 17.9 4l-1-1-.5-.5s1.8 0 2.6.2q1.5.1 3 .7 1 .5 1.8 1.4l1 .9.2-.6.1-.8q.6-1 1.4-1.4l1.6-.7 1.3-.6.7-.4-.2.6-.5 1-.1.4q-.4.8-1 1.4-1 1.2-2.1 1.5l4.3.8q1.7.2 3.2.9l.5.1 1.3.7z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 61.7 191.2)"/><path d="M0 0q-.9-.3-1.3-1.2-.3-.9 0-1.7.3-.9 1.2-1.3A2.3 2.3 0 0 1 3-3q.4.9 0 1.8-.3.9-1.1 1.2Q.9.3 0 0m4-.9q.4-1.2-.2-2.6a3.3 3.3 0 0 0-6 .2q-.5 1.3 0 2.5Q-1.6.6-.3 1t2.5 0Q3.5.3 3.9-1" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 28.6 68)"/><path d="m0 0 .6.9 5.2-3.6-.6-1L-.7-4l3.8-2.7-.6-.8L-2.7-4l.6.9 6 .3z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 35.2 53)"/><path d="m0 0-4.5 4.5.7.7L0 1.5l2 2 .8-.7Z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 47.5 51.5)"/><path d="m0 0 .8.7 4-5-.9-.7Z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 50.7 37)"/><path d="m0 0 1 .5L4-5l-1-.6-5.4 2.3 2.3-4-1-.6-3 5.6.9.5 5.5-2.3z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 64 28.3)"/><path d="m0 0 .3-1-3.2-1 .6-1.7 2.9 1 .3-.8-2.9-1 .6-1.7L1.9-5l.3-1L-2-7.4l-2.1 6z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 78.4 22.3)"/><path d="m0 0 .1-1.7 2.8.2.1-1-2.8-.2.2-2.6-1-.1-.5 6.3 4.2.3v-1z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 96.3 20.1)"/><path d="m0 0 .5 6.3h1L1.1.9l3-.2-.1-1Z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 107.3 27)"/><path d="M0 0q-.5.8-1.4 1-1 .2-1.7-.2-.8-.6-1-1.5t.2-1.7 1.4-1 1.7.2q.9.5 1 1.5Q.5-.7 0 0m-.2-4q-1.1-.7-2.5-.4a3.3 3.3 0 0 0-2.5 4q.3 1.4 1.5 2t2.5.4a3.3 3.3 0 0 0 2.5-4Q1-3.4-.2-4" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 125.7 23.3)"/><path d="M0 0q.4 0 .7.7v1l-1 .6-1.2.6-1-2.1 1.3-.6zm1.7.2Q1-1.2-.3-1l.5-2.8-1.3.6-.5 2.5-1.3.6-.8-2-1 .5 2.6 5.8 2.1-1Q1.5 2.6 1.7 2q.4-.6 0-1.7" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 138.7 30.2)"/><path d="m0 0 1-.6-3.5-5.3-.9.5z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 148.8 31.2)"/><path d="M0 0q-.4.3-.7.3t-.6-.2l-.2-.7.7-1.1q.7-.8.7-1.5.2-.6-.4-1.2-.5-.7-1.3-.7t-1.6.7q-1.2.9-1.4 2.5l1 .1a3 3 0 0 1 1-1.9L-2-4q.4 0 .6.2.3.3.2.7l-.5.9-.7.9-.2.7q-.2.7.4 1.3t1.3.7T.7.7l.8-.9.4-1-1-.3-.3.8z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 157.9 39)"/><path d="m0 0-4-3.5-.7.8 4 3.5L-2 2.3l.8.6L2-.8l-.7-.6z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 167.7 49)"/><path d="m0 0 1 .2q.5.4.5.7 0 .5-.4 1.2L.3 3.2-1.6 2l.7-1q.5-.8.9-1m1.5-.7Q.2-1.5-.9-.7l-1-2.5-.8 1.1 1 2.4-.7 1.2L-4.2.4l-.6.9L.6 4.7l1.2-2q.9-1.3.7-2 0-.8-1-1.4" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 174 62.2)"/><path d="m0 0-.4 1 2.3 1 2.6 3.6.5-1-2-2.8 3.3-.5.5-1-4.5.7Z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 175.3 75)"/><path d="M0 0v-2.3h-7.8v-3.9h7v-2.2h-7v-3.9h8v-2.3h-10.5V0Z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 71.2 78.1)"/><path d="M0 0q0 5-5.8 5h-2.4V-5h2.7q2.7 0 4 1.3Q0-2.5 0 0m.4 5.4q2-1.9 2-5.3t-2-5.4-6.2-2h-4.9V7.3h5q4 0 6-2" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 95.5 87.9)"/><path d="M0 0v-2.3h-7.8v-3.9h7v-2.2h-7v-3.9h8v-2.3h-10.5V0Z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 122.4 78.1)"/><path d="M0 0h2.5v-14.6H-.2L-8.5-4v-10.6H-11V0h2.5L0-11Z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 147.1 78.1)"/><path d="M0 0v-4h6.5v-2.3H0v-6h-2.5V2.3h9.8V0Z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 22.9 113.8)"/><path d="M0 0v14.6h2.5V2.3H9V0Z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 42 130.2)"/><path d="M0 0a5 5 0 0 1-3.7 1.5 5 5 0 0 1-5.2-5.3A5 5 0 0 1-3.6-9a5 5 0 0 1 5.2 5.3Q1.5-1.5 0 0m1.8-9.2a8 8 0 0 0-5.5-2.1 7.5 7.5 0 0 0-7.7 7.5q0 3.3 2.2 5.4a8 8 0 0 0 5.5 2.2A7.5 7.5 0 0 0 4-3.8Q4-7 1.8-9.2" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 76.7 115.3)"/><path d="m0 0 3.3 10.5h2.2L8.7 0l3.7 10.5h2.7L10-4H7.5l-3 10h-.2l-3-10h-2.5l-5.1 14.6h2.6z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 97.7 124.7)"/><path d="M0 0v-2.3h-7.8v-3.9h7v-2.2h-7v-3.9h8v-2.3h-10.5V0Z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 140.1 110.7)"/><path d="M0 0q.8.6.8 2 0 1.5-.8 2t-2.8.6h-3.1V-.6h3Q-.6-.6 0 0m3.3 2q0-3.5-3.2-4.5L4-7.8H.8l-3.5 5h-3.2v-5h-2.5V6.8h5.5q3.3 0 4.7-1.1T3.3 2" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 161.4 119.8)"/><path d="M0 0q-1 0-1.8-.4-.7-.5-.7-1.4t.7-1.3q.8-.5 3-1 2.2-.7 3.4-1.6 1-1 1.1-2.9 0-1.9-1.4-3Q2.8-13 .5-13q-3.4 0-6.1 2.4l1.5 1.9a7 7 0 0 1 4.6-2q1.2 0 2 .5.6.6.6 1.4 0 .9-.6 1.3a7 7 0 0 1-2.3.9l-2.4.7q-.9.3-1.5.8Q-5-4-5-2t1.4 3.2a6 6 0 0 0 3.7 1q1.5.1 2.8-.4Q4.3 1.4 5.3.5L3.9-1.3l-1.7 1z" style="fill:#294634;fill-opacity:1;fill-rule:nonzero;stroke:none" transform="matrix(1.33333 0 0 -1.33333 182 113.2)"/></svg>
<script>location.replace(location.href);</script>
</body>
</html>`;

// The launch screen's own request for the real page must reach the network,
// or it would answer itself forever. It is a window by then, but a moment's
// memory covers a browser that doesn't list it yet.
let launchScreenServedAt = 0;

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.mode !== "navigate" || request.method !== "GET") return;

  event.respondWith(
    (async () => {
      const windows = await self.clients.matchAll({
        type: "window",
        includeUncontrolled: true,
      });
      const justServed = Date.now() - launchScreenServedAt < 10_000;

      if (windows.length > 0 || justServed) return fetch(request);

      launchScreenServedAt = Date.now();
      return new Response(launchScreen, {
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    })(),
  );
});

self.addEventListener("push", (event) => {
  const { title, body, tag, url } = event.data.json();

  event.waitUntil(
    (async () => {
      // A retried push carries the same tag, so it replaces its notification
      // rather than adding one.
      await self.registration.showNotification(title, {
        body,
        tag,
        data: { url },
        icon: "/web-app-manifest-192x192.png",
      });

      // The badge counts the order notifications still in Notification Centre.
      const shown = await self.registration.getNotifications();
      await navigator.setAppBadge?.(shown.length);
    })(),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = new URL(
    event.notification.data?.url ?? "/admin",
    self.location.origin,
  ).href;

  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({ type: "window" });
      const admin = windows.find((client) =>
        new URL(client.url).pathname.startsWith("/admin"),
      );

      if (admin) {
        await admin.focus();
        const navigated = await admin.navigate(url).catch(() => null);
        if (navigated) return;
      }

      await self.clients.openWindow(url);
    })(),
  );
});
