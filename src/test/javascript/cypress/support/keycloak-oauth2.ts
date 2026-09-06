/* eslint-disable @typescript-eslint/camelcase */
/* eslint-disable @typescript-eslint/no-namespace */
/* eslint-disable @typescript-eslint/no-use-before-define */
// eslint-disable-next-line spaced-comment
/// <reference types="cypress" />

// Cypress 6 cy.request() to http://localhost:7419/oauth2/authorization/oidc
// hangs 30s with no response on ubuntu-latest (Node 14). The same URL returns
// HTTP 302 in <50ms via curl (see run-app-ci.sh probe). Force IPv4 and use
// curl for the no-follow authorization hop; use cy.visit so Chrome follows
// the OIDC redirect after Keycloak has a session.

function appOrigin(): string {
  return (Cypress.config('baseUrl') || 'http://localhost:7419/').replace('localhost', '127.0.0.1').replace(/\/$/, '');
}

function ipv4(urlOrOrigin: string): string {
  return urlOrOrigin.replace('://localhost', '://127.0.0.1');
}

Cypress.Commands.add('getOauth2Data', () => {
  const url = `${appOrigin()}/oauth2/authorization/oidc`;
  cy.exec(`curl -sS --max-time 10 --max-redirs 0 -D - -o /dev/null "${url}"`, { failOnNonZeroExit: true }).then(result => {
    const match = /(?:^|\n)Location:\s*(\S+)/i.exec(result.stdout);
    if (!match) {
      throw new Error(`No Location header from ${url}: ${result.stdout}`);
    }
    const location = new URL(match[1].trim());
    const realmMatch = /\/realms\/([^/]+)/.exec(location.pathname);
    const realm = realmMatch ? realmMatch[1] : location.pathname.split('/')[3];
    const clientId = location.searchParams.get('client_id');
    const origin = ipv4(location.origin);
    const data = {
      url: location,
      realmPath: `${origin}/auth/realms/${realm}`,
      realm,
      clientId,
    };
    cy.wrap(data).as('oauth2Data');
  });
});

Cypress.Commands.add('keycloackLogin', (oauth2Data: any, user: string) => {
  Cypress.log({ name: 'Login' });

  cy.fixture(`users/${user}`).then(userData => {
    cy.request({
      url: `${oauth2Data.realmPath}/protocol/openid-connect/auth`,
      followRedirect: false,
      qs: {
        scope: 'openid',
        response_type: 'code',
        approval_prompt: 'auto',
        redirect_uri: ipv4(String(Cypress.config('baseUrl'))),
        client_id: oauth2Data.clientId,
      },
    })
      .then(response => {
        const html = document.createElement('html');
        html.innerHTML = response.body;

        const form = html.getElementsByTagName('form')[0];
        const url = ipv4(form.action);

        return cy.request({
          method: 'POST',
          url,
          followRedirect: false,
          form: true,
          body: {
            username: userData.username,
            password: userData.password,
          },
        });
      })
      .then(() => {
        // Chrome follows the 302 through Keycloak using the session from the
        // form POST (cy.request cookies are visible to cy.visit). cy.request
        // followRedirect:true on this URL is the 30s hang.
        cy.visit('/oauth2/authorization/oidc');
      });
  });
});

Cypress.Commands.add('keycloackLogout', (oauth2Data: any) => {
  return cy.request({
    url: `${oauth2Data.realmPath}/protocol/openid-connect/logout`,
  });
});

Cypress.Commands.add('clearCache', () => {
  cy.clearCookies();
  cy.clearLocalStorage();
  cy.window().then(win => {
    win.sessionStorage.clear();
  });
});

declare global {
  namespace Cypress {
    interface Chainable<Subject> {
      getOauth2Data(): Cypress.Chainable;
      keycloackLogin(oauth2Data: any, user: string): Cypress.Chainable;
      keycloackLogout(oauth2Data: any): Cypress.Chainable;
      clearCache(): Cypress.Chainable;
    }
  }
}

// Convert this to a module instead of script (allows import/export)
export {};
