// Exercise the real Cypress helper without starting Java, Docker, or a browser.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const ts = require('typescript');

const helper = path.resolve(__dirname, '../../src/test/javascript/cypress/support/keycloak-oauth2.ts');
const source = ts.transpileModule(fs.readFileSync(helper, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2019 },
}).outputText;
const authorizationUrl = new URL('http://localhost:9080/auth/realms/jhipster/protocol/openid-connect/auth');
authorizationUrl.searchParams.set('client_id', 'web_app');
authorizationUrl.searchParams.set('redirect_uri', 'http://localhost:7419/login/oauth2/code/oidc');
authorizationUrl.searchParams.set('response_type', 'code');
authorizationUrl.searchParams.set('scope', 'openid profile');
authorizationUrl.searchParams.set('state', 'fixture-state');
const loginAction = 'http://localhost:9080/auth/realms/jhipster/login-actions/authenticate?session_code=fixture';

function harness({ missingForm = false, postStatus = 302 } = {}) {
  const commands = {};
  const requests = [];
  const visits = [];
  const aliases = {};
  const chain = value => ({
    then(callback) {
      const result = callback(value);
      return result && typeof result.then === 'function' ? result : chain(result);
    },
    as(name) {
      aliases[name] = value;
      return chain(value);
    },
  });
  const cy = {
    exec: () => chain({ stdout: `HTTP/1.1 302 Found\nLocation: ${authorizationUrl}\n` }),
    wrap: chain,
    fixture: () => chain({ username: 'fixture-user', password: 'fixture-password' }),
    request(options) {
      requests.push(options);
      if (options.method === 'POST') {
        return chain({ status: postStatus, headers: postStatus === 302 ? { location: 'http://localhost:7419/login/oauth2/code/oidc' } : {} });
      }
      // A redirect response has no login form. Following it yields the page.
      const followed = options.followRedirect !== false;
      return chain({ status: followed ? 200 : 302, body: followed && !missingForm ? 'login-form' : '' });
    },
    visit: url => visits.push(url),
  };
  const document = {
    createElement() {
      return {
        innerHTML: '',
        querySelector(selector) {
          assert.strictEqual(selector, 'form#kc-form-login');
          return this.innerHTML === 'login-form' ? { getAttribute: () => loginAction } : null;
        },
      };
    },
  };
  vm.runInNewContext(source, {
    exports: {}, URL, cy, document,
    Cypress: { Commands: { add: (name, fn) => { commands[name] = fn; } }, config: () => 'http://localhost:7419/', log() {} },
  });
  commands.getOauth2Data();
  return { commands, requests, visits, data: aliases.oauth2Data };
}

const good = harness();
assert.strictEqual(good.data.realmPath, 'http://localhost:9080/auth/realms/jhipster');
good.commands.keycloackLogin(good.data, 'user');
assert.strictEqual(good.requests.length, 2);
const requestUrl = new URL(good.requests[0].url);
assert.strictEqual(requestUrl.origin, 'http://localhost:9080');
assert.strictEqual(requestUrl.searchParams.get('redirect_uri'), authorizationUrl.searchParams.get('redirect_uri'));
assert.strictEqual(requestUrl.searchParams.get('state'), 'fixture-state');
assert.strictEqual(requestUrl.searchParams.get('prompt'), 'login');
assert.strictEqual(good.requests[0].followRedirect, true);
assert.strictEqual(good.requests[1].url, loginAction);
assert.strictEqual(good.requests[1].followRedirect, false);
assert.deepStrictEqual(good.visits, ['/oauth2/authorization/oidc']);

const missing = harness({ missingForm: true });
assert.throws(() => missing.commands.keycloackLogin(missing.data, 'user'), /did not return a login form/);
assert.strictEqual(missing.requests.length, 1);
assert.strictEqual(missing.visits.length, 0);

const rejected = harness({ postStatus: 200 });
assert.throws(() => rejected.commands.keycloackLogin(rejected.data, 'user'), /did not accept the login/);
assert.strictEqual(rejected.visits.length, 0);
console.log('OAuth helper: canonical host, complete authorization request, redirects, missing form, and rejected login passed');
