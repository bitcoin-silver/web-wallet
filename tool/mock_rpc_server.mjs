#!/usr/bin/env node
// Local mock of a BTCS RPC proxy, used by test/browser. It is not part of the
// app and never talks to any real node.
//
//   node tool/mock_rpc_server.mjs            (listens on 127.0.0.1:19911)
//
// The path picks the behaviour:
//   /ok           a healthy BTCS node
//   /wrongchain   reports the Bitcoin genesis hash
//   /nocors       healthy, but sends no CORS headers
//   /forbidden    answers getblockhash with HTTP 403 "Method not allowed"
//   /hostilefee   reports absurd fee rates
//   /html         answers everything with an HTML page
//   /drop         resets every connection (a server that is up but unusable)
//   /__sent       raw transactions received by sendrawtransaction
//   /__reset      clears the log
import http from 'node:http';
import { createHash } from 'node:crypto';

const PORT = Number(process.env.PORT ?? 19911);
const GENESIS = '00000ea8e97e04892a03df35947ff0c4df705723f5b18be7cc6456ed16e9788e';
const BITCOIN_GENESIS = '000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f';
const sha256 = (s) => createHash('sha256').update(s).digest('hex');
const BEST_BLOCK = sha256('best block');
const HEIGHT = 5000;

const sent = [];

function methodResult(mode, method, params) {
  const hostile = mode === 'hostilefee';
  switch (method) {
    case 'getblockchaininfo':
      return { chain: 'main', blocks: HEIGHT, headers: HEIGHT, bestblockhash: BEST_BLOCK, difficulty: 1, mediantime: 1700000000 };
    case 'getblockhash':
      if (mode === 'forbidden') return { status: 403, raw: { error: 'Method not allowed' } };
      return params[0] === 0 ? (mode === 'wrongchain' ? BITCOIN_GENESIS : GENESIS) : BEST_BLOCK;
    case 'getblockcount':
      return HEIGHT;
    case 'getnetworkinfo':
      return { version: 210000, subversion: '/MockNode:1.0/', connections: 8,
               relayfee: hostile ? 5 : 0.00001, incrementalfee: hostile ? 5 : 0.00001 };
    case 'getmempoolinfo':
      return { size: 0, bytes: 0, mempoolminfee: hostile ? 5 : 0.00001 };
    case 'getmininginfo':
      return { networkhashps: 1e9 };
    case 'estimatesmartfee':
      return { feerate: hostile ? 200 : 0.00002, blocks: params[0] ?? 6 };
    case 'getrawmempool':
      return [];
    case 'scantxoutset':
      return {
        success: true,
        total_amount: 1.5,
        unspents: [
          { txid: sha256('utxo-1'), vout: 0, amount: 1.0, height: HEIGHT - 10 },
          { txid: sha256('utxo-2'), vout: 1, amount: 0.5, height: HEIGHT - 20 },
        ],
      };
    case 'validateaddress':
      return { isvalid: typeof params[0] === 'string' && params[0].startsWith('bs1') };
    case 'gettxout':
      return { error: { code: -5, message: 'not found' } };
    case 'sendrawtransaction':
      if (typeof params[0] !== 'string' || !/^[0-9a-f]+$/i.test(params[0])) {
        return { error: { code: -22, message: 'TX decode failed' } };
      }
      sent.push(params[0]);
      return sha256(params[0]);
    default:
      return { error: { code: -32601, message: 'Method not found' } };
  }
}

function send(res, status, body, type = 'application/json') {
  res.writeHead(status, { 'Content-Type': type });
  res.end(typeof body === 'string' ? body : JSON.stringify(body));
}

const server = http.createServer((req, res) => {
  const { pathname } = new URL(req.url, 'http://localhost');
  const mode = pathname.slice(1);

  if (mode === 'drop') return req.socket.destroy();

  // Mimics the default proxy: the requesting origin is allowed, POST/OPTIONS only.
  if (mode !== 'nocors') {
    res.setHeader('Access-Control-Allow-Origin', req.headers.origin ?? '*');
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  }
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }

  if (pathname === '/__sent') return send(res, 200, sent);
  if (pathname === '/__reset') { sent.length = 0; return send(res, 200, {}); }
  if (req.method !== 'POST') return send(res, 405, { error: 'Use POST' });

  let raw = '';
  req.on('data', (chunk) => (raw += chunk));
  req.on('end', () => {
    if (mode === 'html') return send(res, 200, '<html><body>Not a node</body></html>', 'text/html');
    let call;
    try { call = JSON.parse(raw); } catch { return send(res, 400, { error: 'Bad JSON' }); }

    const out = methodResult(mode, call.method, call.params ?? []);
    if (out && out.raw) return send(res, out.status, out.raw);
    // The default proxy rewrites jsonrpc and id.
    const base = { jsonrpc: '2.0', id: 'BTCS-RPC-PROXY' };
    if (out && out.error) return send(res, 200, { ...base, error: out.error });
    return send(res, 200, { ...base, result: out });
  });
});

server.listen(PORT, '127.0.0.1', () => console.log(`mock BTCS rpc on http://127.0.0.1:${PORT}`));
