import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const worker = readFileSync(
  new URL("../../priv/static/admin-sw.js", import.meta.url),
  "utf8",
);

const fixture = ({ windows = [] } = {}) => {
  const listeners = new Map();
  const fetched = [];
  let now = 1_000_000;

  const self = {
    addEventListener: (name, callback) => listeners.set(name, callback),
    skipWaiting() {},
    clients: { matchAll: async () => windows, claim: async () => {} },
  };

  vm.runInNewContext(worker, {
    self,
    Response,
    Date: { now: () => now },
    fetch: async (request) => {
      fetched.push(request);
      return new Response("network");
    },
  });

  const navigate = async ({ method = "GET", mode = "navigate" } = {}) => {
    let reply = null;
    listeners.get("fetch")({
      request: { method, mode, url: "https://edenflowers.fi/admin" },
      respondWith: (promise) => (reply = promise),
    });
    return reply && (await (await reply).text());
  };

  return {
    navigate,
    fetched,
    later: (ms) => (now += ms),
  };
};

test("a launch with no open window gets the launch screen", async () => {
  const { navigate, fetched } = fixture();

  const page = await navigate();

  assert.match(page, /location\.replace\(location\.href\)/);
  assert.equal(fetched.length, 0);
});

test("the launch screen's own reload reaches the network", async () => {
  const { navigate, fetched, later } = fixture();

  await navigate();
  later(500);

  assert.equal(await navigate(), "network");
  assert.equal(fetched.length, 1);
});

test("navigating with the app already open reaches the network", async () => {
  const { navigate } = fixture({
    windows: [{ url: "https://edenflowers.fi/admin" }],
  });

  assert.equal(await navigate(), "network");
});

test("a later launch gets the launch screen again", async () => {
  const { navigate, later } = fixture();

  await navigate();
  later(60_000);

  assert.match(await navigate(), /location\.replace/);
});

test("form posts and subresources are left to the browser", async () => {
  const { navigate } = fixture();

  assert.equal(await navigate({ method: "POST" }), null);
  assert.equal(await navigate({ mode: "cors" }), null);
});
