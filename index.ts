import { v4 as uuidv4 } from 'uuid';

const port = parseInt(process.env.PORT || '8080', 10);

// Health endpoint
async function healthHandler(req: Request): Promise<Response> {
  return new Response(
    JSON.stringify({
      status: 'ok',
      service: 'bun-sample',
      timestamp: new Date().toISOString(),
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }
  );
}

// Root endpoint
async function rootHandler(req: Request): Promise<Response> {
  return new Response(
    JSON.stringify({
      message: 'Hello from Bun sample',
      uuid: uuidv4(),
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }
  );
}

// Info endpoint
async function infoHandler(req: Request): Promise<Response> {
  return new Response(
    JSON.stringify({
      service: 'bun-sample',
      timestamp: new Date().toISOString(),
      note: 'New info endpoint to verify sync/restart',
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }
  );
}

// Echo endpoint
async function echoHandler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  return new Response(
    JSON.stringify({
      method: req.method,
      path: url.pathname,
      query: url.search,
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }
  );
}

// Main router
async function handleRequest(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;

  if (path === '/health') {
    return healthHandler(req);
  } else if (path === '/info') {
    return infoHandler(req);
  } else if (path === '/echo') {
    return echoHandler(req);
  } else if (path === '/') {
    return rootHandler(req);
  } else {
    return new Response(
      JSON.stringify({ error: 'Not found' }),
      {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
}

// Start server
const server = Bun.serve({
  port,
  hostname: '0.0.0.0',
  fetch: handleRequest,
});

console.log(`Bun server running on http://0.0.0.0:${port}`);

