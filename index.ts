import { v4 as uuidv4 } from 'uuid';
import { format, formatDistanceToNow } from 'date-fns';
import { nanoid } from 'nanoid';
import { z } from 'zod';
import _ from 'lodash';
import CryptoJS from 'crypto-js';

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

// Time endpoint - uses date-fns for formatted dates
async function timeHandler(req: Request): Promise<Response> {
  const now = new Date();
  return new Response(
    JSON.stringify({
      iso: now.toISOString(),
      formatted: format(now, 'PPpp'), // Pretty format: "Dec 1, 2025 at 12:00 AM"
      relative: formatDistanceToNow(now, { addSuffix: true }), // "in a few seconds"
      unix: Math.floor(now.getTime() / 1000),
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }
  );
}

// Random ID endpoint - uses nanoid for short, URL-safe IDs
async function randomIdHandler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const size = parseInt(url.searchParams.get('size') || '21', 10);
  return new Response(
    JSON.stringify({
      id: nanoid(size),
      size: size,
      type: 'nanoid',
      note: 'Short, URL-safe random ID',
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }
  );
}

// Encrypt endpoint - uses crypto-js for encryption
async function encryptHandler(req: Request): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed. Use POST.' }),
      {
        status: 405,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
  
  try {
    const body = await req.json();
    const text = body.text || '';
    const key = body.key || 'default-key';
    
    const encrypted = CryptoJS.AES.encrypt(text, key).toString();
    
    return new Response(
      JSON.stringify({
        original: text,
        encrypted: encrypted,
        algorithm: 'AES',
      }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: 'Invalid JSON' }),
      {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
}

// Utils endpoint - uses lodash for utility functions
async function utilsHandler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const action = url.searchParams.get('action') || 'shuffle';
  const input = url.searchParams.get('input') || '1,2,3,4,5';
  
  const arr = input.split(',').map(s => s.trim());
  let result;
  
  switch (action) {
    case 'shuffle':
      result = _.shuffle(arr);
      break;
    case 'chunk':
      const size = parseInt(url.searchParams.get('size') || '2', 10);
      result = _.chunk(arr, size);
      break;
    case 'unique':
      result = _.uniq(arr);
      break;
    default:
      result = arr;
  }
  
  return new Response(
    JSON.stringify({
      action: action,
      input: arr,
      result: result,
      library: 'lodash',
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }
  );
}

// Validate endpoint - uses zod for schema validation
async function validateHandler(req: Request): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed. Use POST.' }),
      {
        status: 405,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
  
  try {
    const body = await req.json();
    const schema = z.object({
      email: z.string().email(),
      age: z.number().int().min(18).max(120),
    });
    
    const validated = schema.parse(body);
    return new Response(
      JSON.stringify({
        valid: true,
        data: validated,
        message: 'Validation successful',
      }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  } catch (error) {
    if (error instanceof z.ZodError) {
      return new Response(
        JSON.stringify({
          valid: false,
          errors: error.errors,
        }),
        {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        }
      );
    }
    return new Response(
      JSON.stringify({ error: 'Invalid JSON' }),
      {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
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
  } else if (path === '/time') {
    return timeHandler(req);
  } else if (path === '/random-id') {
    return randomIdHandler(req);
  } else if (path === '/validate') {
    return validateHandler(req);
  } else if (path === '/utils') {
    return utilsHandler(req);
  } else if (path === '/encrypt') {
    return encryptHandler(req);
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

