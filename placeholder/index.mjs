// Placeholder handler. Terraform deploys it until a package with the real code
// is supplied (docs/infrastructure.md, section "Function package").
//
// The event is an API Gateway HTTP API event (payload format 2.0).
export const handler = async (event) => ({
  statusCode: 200,
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({
    service: process.env.PROJECT_NAME,
    environment: process.env.ENVIRONMENT,
    placeholder: true,
    method: event.requestContext?.http?.method,
    path: event.rawPath,
  }),
});
