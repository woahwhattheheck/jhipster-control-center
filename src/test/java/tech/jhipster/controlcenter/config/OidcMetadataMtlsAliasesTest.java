package tech.jhipster.controlcenter.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

import com.nimbusds.oauth2.sdk.as.AuthorizationServerEndpointMetadata;
import com.nimbusds.openid.connect.sdk.op.OIDCProviderMetadata;
import java.net.URI;
import org.junit.jupiter.api.Test;

/**
 * Regression coverage for
 * <a href="https://github.com/jhipster/jhipster-control-center/issues/174">#174</a>.
 *
 * <p>Keycloak 12 and later advertise an {@code mtls_endpoint_aliases} object in their OpenID
 * Connect discovery document. On the {@code com.nimbusds:oauth2-oidc-sdk} 7.x line,
 * {@code JSONObjectUtils.getGeneric} rejects that member with
 * {@code ParseException: Unexpected type of JSON object member with key mtls_endpoint_aliases},
 * which aborts {@code ClientRegistrations.fromIssuerLocation} and stops the control center from
 * starting against a modern Keycloak.
 *
 * <p>The 7.x line reaches this build through the OAuth2 client starter: Spring Boot 2.3.1
 * manages {@code oauth2-oidc-sdk} 7.1.1, whereas the Boot 2.4.x generation used by the rest of
 * the application manages 8.36. These tests drive the exact SDK entry point named in the
 * reported stack trace and assert that {@code mtls_endpoint_aliases} is not merely tolerated but
 * parsed and retained.
 */
class OidcMetadataMtlsAliasesTest {

    private static final String ISSUER = "http://keycloak:9080/auth/realms/jhipster";

    private static final String MTLS_TOKEN_ENDPOINT = ISSUER + "/protocol/openid-connect/token/mtls";

    private static final String MTLS_AUTHORIZATION_ENDPOINT = ISSUER + "/protocol/openid-connect/auth/mtls";

    /**
     * Builds a trimmed but valid Keycloak discovery document. Single quotes are used purely for
     * readability and swapped for JSON double quotes before returning.
     *
     * @param withMtlsAliases whether to advertise the {@code mtls_endpoint_aliases} object.
     */
    private static String keycloakDiscoveryDocument(boolean withMtlsAliases) {
        StringBuilder json = new StringBuilder();
        json.append("{");
        json.append("'issuer': '").append(ISSUER).append("',");
        json.append("'authorization_endpoint': '").append(ISSUER).append("/protocol/openid-connect/auth',");
        json.append("'token_endpoint': '").append(ISSUER).append("/protocol/openid-connect/token',");
        json.append("'jwks_uri': '").append(ISSUER).append("/protocol/openid-connect/certs',");
        json.append("'response_types_supported': ['code', 'id_token', 'token id_token'],");
        json.append("'subject_types_supported': ['public', 'pairwise'],");
        json.append("'id_token_signing_alg_values_supported': ['RS256']");
        if (withMtlsAliases) {
            json.append(",'mtls_endpoint_aliases': {");
            json.append("'token_endpoint': '").append(MTLS_TOKEN_ENDPOINT).append("',");
            json.append("'authorization_endpoint': '").append(MTLS_AUTHORIZATION_ENDPOINT).append("'");
            json.append("}");
        }
        json.append("}");
        return json.toString().replace('\'', '"');
    }

    @Test
    void parsesDiscoveryDocumentContainingMtlsEndpointAliases() {
        assertThatCode(() -> OIDCProviderMetadata.parse(keycloakDiscoveryDocument(true))).doesNotThrowAnyException();
    }

    @Test
    void retainsMtlsEndpointAliasesInsteadOfDiscardingThem() throws Exception {
        OIDCProviderMetadata metadata = OIDCProviderMetadata.parse(keycloakDiscoveryDocument(true));

        assertThat(metadata.getIssuer().getValue()).isEqualTo(ISSUER);

        AuthorizationServerEndpointMetadata aliases = metadata.getMtlsEndpointAliases();
        assertThat(aliases).as("mtls_endpoint_aliases must be parsed, not skipped").isNotNull();
        assertThat(aliases.getTokenEndpointURI()).isEqualTo(URI.create(MTLS_TOKEN_ENDPOINT));
        assertThat(aliases.getAuthorizationEndpointURI()).isEqualTo(URI.create(MTLS_AUTHORIZATION_ENDPOINT));
    }

    @Test
    void stillParsesDiscoveryDocumentWithoutMtlsEndpointAliases() throws Exception {
        OIDCProviderMetadata metadata = OIDCProviderMetadata.parse(keycloakDiscoveryDocument(false));

        assertThat(metadata.getIssuer().getValue()).isEqualTo(ISSUER);
        assertThat(metadata.getMtlsEndpointAliases()).isNull();
    }
}
