package tech.jhipster.controlcenter.web.filter;

import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;

@Component
public class SpaWebFilter implements WebFilter {

    /**
     * Forwards any unmapped paths (except those containing a period) to the client {@code index.html}.
     */
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String path = exchange.getRequest().getURI().getPath();
        if (
            !path.startsWith("/api") &&
            !path.startsWith("/management") &&
            !path.startsWith("/services") &&
            !path.startsWith("/swagger") &&
            !path.startsWith("/v2/api-docs") &&
            !path.startsWith("/v3/api-docs") &&
            // jhcc-custom: /login and /oauth2 are Spring Security OIDC endpoints.
            // Rewriting /oauth2/authorization/oidc to index.html makes Cypress
            // cy.request hang for 30s instead of following the Keycloak 302.
            !path.startsWith("/login") &&
            !path.startsWith("/oauth2") &&
            !path.startsWith("/gateway") &&
            path.matches("[^\\\\.]*")
        ) {
            return chain.filter(exchange.mutate().request(exchange.getRequest().mutate().path("/index.html").build()).build());
        }
        return chain.filter(exchange);
    }
}
