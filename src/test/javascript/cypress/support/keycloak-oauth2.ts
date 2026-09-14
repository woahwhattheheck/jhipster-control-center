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
    const data = {
      url: location,
      realmPath: `${location.origin}${location.pathname.split('/protocol/')[0]}`,
      realm,
      clientId,
    };
    cy.wrap(data).as('oauth2Data');
  });
});

Cypress.Commands.add('keycloackLogin', (oauth2Data: any, user: string) => {
  Cypress.log({ name: 'Login' });

  cy.fixture(`users/${user}`).then(userData => {
    // Preserve Keycloak's advertised hostname and the application's complete
    // authorization request. Rewriting localhost to 127.0.0.1 splits the
    // login cookies from the browser session; a redirect is not a login form.
    const authorizationUrl = new URL(oauth2Data.url.toString());
    authorizationUrl.searchParams.set('prompt', 'login');
    cy.request({
      url: authorizationUrl.toString(),
      followRedirect: true,
    })
      .then(response => {
        const html = document.createElement('html');
        html.innerHTML = response.body;

        const form = html.querySelector('form#kc-form-login');
        const action = form && form.getAttribute('action');
        if (response.status !== 200 || !action) {
          throw new Error(`Keycloak did not return a login form (HTTP ${response.status})`);
        }
        const url = new URL(action, authorizationUrl.toString()).toString();

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
      .then(response => {
        if (response.status !== 302 || !response.headers.location) {
          throw new Error(`Keycloak did not accept the login (HTTP ${response.status})`);
        }
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
