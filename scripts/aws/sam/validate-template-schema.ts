import { readFileSync } from 'fs'
import yaml from 'js-yaml'
import { z } from 'zod'

const CFN_SCHEMA = yaml.DEFAULT_SCHEMA.extend(
  ['!And','!Base64','!Cidr','!Condition','!Equals','!FindInMap','!GetAtt',
   '!GetAZs','!If','!ImportValue','!Join','!Not','!Or','!Ref','!Select',
   '!Split','!Sub','!Transform','!ValueOf']
  .flatMap(tag => [
    new yaml.Type(tag, { construct: (d: unknown) => ({ [tag]: d }), kind: 'scalar' }),
    new yaml.Type(tag, { construct: (d: unknown) => ({ [tag]: d }), kind: 'sequence' }),
    new yaml.Type(tag, { construct: (d: unknown) => ({ [tag]: d }), kind: 'mapping' }),
  ])
)

const templatePath = process.env['TEMPLATE'] || 'deploy/template.yml'
const expectedResources: string[] = JSON.parse(process.env['EXPECTED_RESOURCES'] || '[]')
const containerPort = Number(process.env['CONTAINER_PORT'] || '5090')
const structuralOnly = process.env['STRUCTURAL_ONLY'] === 'true'
const ENVIRONMENTS = ['dev', 'build', 'staging', 'integration', 'production'] as const

const raw = yaml.load(readFileSync(templatePath, 'utf8'), { schema: CFN_SCHEMA }) as Record<string, unknown>

// --- Schemas ---

const CfnParameterSchema = z.object({
  Type: z.string(),
  Description: z.string().optional(),
  Default: z.union([z.string(), z.number()]).optional(),
  AllowedValues: z.array(z.string()).optional(),
  AllowedPattern: z.string().optional(),
})

const CfnResourceSchema = z.object({
  Type: z.string().regex(/^AWS::/),
  Condition: z.string().optional(),
  DependsOn: z.union([z.string(), z.array(z.string())]).optional(),
  Properties: z.record(z.string(), z.unknown()).optional(),
})

const CfnTemplateSchema = z.object({
  AWSTemplateFormatVersion: z.string(),
  Description: z.string(),
  Parameters: z.record(z.string(), CfnParameterSchema),
  Conditions: z.record(z.string(), z.unknown()),
  Mappings: z.record(z.string(), z.record(z.string(), z.record(z.string(), z.unknown()))),
  Resources: z.record(z.string(), CfnResourceSchema),
  Outputs: z.record(z.string(), z.object({
    Value: z.unknown(),
    Description: z.string().optional(),
    Export: z.object({ Name: z.unknown() }).optional(),
  })).optional(),
})

// --- Structural validation ---

const result = CfnTemplateSchema.safeParse(raw)
if (!result.success) {
  console.error('❌ Schema validation failed:')
  const sanitized = JSON.stringify(result.error.format(), null, 2).replace(/[\r\n]+/g, ' ')
  console.error(sanitized)
  process.exit(1)
}

console.log(`✓ ${templatePath} passed structural validation`)

if (structuralOnly) process.exit(0)

// --- Assertion helpers ---

const { Parameters, Conditions, Mappings, Resources, Outputs } = result.data
const failures: string[] = []

function assert(condition: boolean, message: string) {
  if (!condition) failures.push(`✗ ${message}`)
  else console.log(`✓ ${message}`)
}

// --- Transform ---

assert(
  'Transform' in raw && String(raw['Transform']).includes('AWS::Serverless-2016-10-31'),
  'has SAM transform'
)

// --- Parameters ---

for (const name of ['Environment','VpcStackName','PermissionsBoundary','CodeSigningConfigArn','DeploymentStrategy','LogGroupRetentionInDays']) {
  assert(name in Parameters, `has parameter ${name}`)
}

const envPattern = new RegExp(Parameters['Environment']?.AllowedPattern ?? '$^')
for (const env of ENVIRONMENTS) {
  assert(envPattern.test(env), `Environment AllowedPattern matches '${env}'`)
}

assert(Parameters['LogGroupRetentionInDays']?.Default === '30', "LogGroupRetentionInDays defaults to '30'")
assert(Parameters['PermissionsBoundary']?.Default === 'none', "PermissionsBoundary defaults to 'none'")
assert(Parameters['CodeSigningConfigArn']?.Default === 'none', "CodeSigningConfigArn defaults to 'none'")

// --- Conditions ---

for (const name of ['IsNotDevelopment','IsProduction','UsePermissionsBoundary','UseCodeSigning','UseCanaryDeployment']) {
  assert(name in Conditions, `has condition ${name}`)
}

// --- Outputs ---

if (Outputs) {
  for (const name of ['URL', 'APIGatewayID']) {
    assert(name in Outputs, `has output ${name}`)
  }
  assert(Outputs['APIGatewayID']?.Export !== undefined, 'APIGatewayID output is exported')
}

// --- Mappings ---

assert('EnvironmentConfiguration' in Mappings, 'Mappings has EnvironmentConfiguration')
assert('FeatureFlagMapping' in Mappings, 'Mappings has FeatureFlagMapping')
assert('ElasticLoadBalancerAccountIds' in Mappings, 'Mappings has ElasticLoadBalancerAccountIds')
assert('AccountId' in (Mappings['ElasticLoadBalancerAccountIds']?.['eu-west-2'] ?? {}), 'ElasticLoadBalancerAccountIds has eu-west-2 AccountId')

for (const env of ENVIRONMENTS) {
  const config = Mappings['EnvironmentConfiguration']?.[env]
  assert(config !== undefined, `EnvironmentConfiguration has entry for ${env}`)
  for (const key of ['logLevel','dynatraceSecretArn','sessionStoreSecretArn','fargateCPUsize','fargateRAMsize','minECSCount','maxECSCount','nodeEnv']) {
    assert(config !== undefined && key in config, `EnvironmentConfiguration[${env}] has ${key}`)
  }
  const flags = Mappings['FeatureFlagMapping']?.[env]
  assert(flags !== undefined && 'ga4Enabled' in flags, `FeatureFlagMapping[${env}] has ga4Enabled`)
  assert(flags !== undefined && 'deviceIntelligenceEnabled' in flags, `FeatureFlagMapping[${env}] has deviceIntelligenceEnabled`)
}

for (const env of ['build', 'production'] as const) {
  const config = Mappings['EnvironmentConfiguration']?.[env]
  assert(config?.['fargateCPUsize'] === '2048', `EnvironmentConfiguration[${env}] fargateCPUsize is 2048`)
  assert(config?.['fargateRAMsize'] === '4096', `EnvironmentConfiguration[${env}] fargateRAMsize is 4096`)
}

for (const env of ['dev', 'staging'] as const) {
  const config = Mappings['EnvironmentConfiguration']?.[env]
  assert(config?.['fargateCPUsize'] === '256', `EnvironmentConfiguration[${env}] fargateCPUsize is 256`)
  assert(config?.['fargateRAMsize'] === '512', `EnvironmentConfiguration[${env}] fargateRAMsize is 512`)
}

// --- Expected resources (from input) ---

for (const name of expectedResources) {
  assert(name in Resources, `has resource ${name}`)
  assert(Resources[name]?.Type.startsWith('AWS::'), `resource ${name} has valid AWS Type`)
}

// --- Resource-level assertions ---

const lb = Resources['LoadBalancer']?.Properties
assert(lb?.['Scheme'] === 'internal', 'LoadBalancer is internal scheme')
assert(lb?.['Type'] === 'application', 'LoadBalancer is application type')

const taskDef = Resources['ECSServiceTaskDefinition']?.Properties
assert(
  Array.isArray(taskDef?.['RequiresCompatibilities']) &&
  (taskDef['RequiresCompatibilities'] as string[]).includes('FARGATE'),
  'ECSServiceTaskDefinition uses FARGATE'
)
assert(taskDef?.['NetworkMode'] === 'awsvpc', 'ECSServiceTaskDefinition uses awsvpc network mode')

const container = (taskDef?.['ContainerDefinitions'] as Record<string, unknown>[])?.[0]
assert(container?.['ReadonlyRootFilesystem'] === true, 'ECS container uses readonly root filesystem')
assert(
  (container?.['PortMappings'] as { ContainerPort: number }[] | undefined)?.[0]?.ContainerPort === containerPort,
  `ECS container exposes port ${containerPort}`
)

assert(Resources['ECSAccessLogsGroup']?.Properties?.['RetentionInDays'] !== undefined, 'ECSAccessLogsGroup has RetentionInDays')
assert(Resources['APIGatewayAccessLogsGroup']?.Properties?.['RetentionInDays'] !== undefined, 'APIGatewayAccessLogsGroup has RetentionInDays')

const sessionsTable = Resources['SessionsTable']?.Properties
assert(sessionsTable?.['BillingMode'] === 'PAY_PER_REQUEST', 'SessionsTable uses PAY_PER_REQUEST billing')
assert((sessionsTable?.['TimeToLiveSpecification'] as Record<string, unknown>)?.['AttributeName'] === 'expires', "SessionsTable TTL on 'expires'")
assert((sessionsTable?.['TimeToLiveSpecification'] as Record<string, unknown>)?.['Enabled'] === true, 'SessionsTable TTL enabled')
assert((sessionsTable?.['SSESpecification'] as Record<string, unknown>)?.['SSEEnabled'] === true, 'SessionsTable SSE enabled')

const lbSGIngress = (Resources['LoadBalancerSG']?.Properties?.['SecurityGroupIngress'] as { FromPort: number; ToPort: number }[])?.[0]
assert(lbSGIngress?.FromPort === 80 && lbSGIngress?.ToPort === 80, 'LoadBalancerSG allows ingress on port 80')

const ecsIngress = Resources['ECSSecurityGroupIngressFromLoadBalancer']?.Properties
assert(
  ecsIngress?.['FromPort'] === containerPort && ecsIngress?.['ToPort'] === containerPort,
  `ECSSecurityGroupIngressFromLoadBalancer allows port ${containerPort}`
)

assert(Resources['APIGatewayHTTPEndpoint']?.Properties?.['ProtocolType'] === 'HTTP', 'APIGatewayHTTPEndpoint uses HTTP protocol')
assert(Resources['APIGatewayRoute']?.Properties?.['RouteKey'] === 'ANY /{proxy+}', 'APIGatewayRoute uses ANY proxy route key')

const clusterSettings = Resources['EcsCluster']?.Properties?.['ClusterSettings'] as { Name: string; Value: string }[] | undefined
assert(clusterSettings?.find(s => s.Name === 'containerInsights')?.Value === 'enabled', 'EcsCluster has containerInsights enabled')

assert(Resources['LoggingKmsKey']?.Properties?.['EnableKeyRotation'] === true, 'LoggingKmsKey has key rotation enabled')

const bucket = Resources['AccessLogsBucket']
assert((bucket as Record<string, unknown>)?.['Condition'] === 'IsNotDevelopment', 'AccessLogsBucket is conditional on IsNotDevelopment')
assert((bucket?.Properties?.['VersioningConfiguration'] as Record<string, unknown>)?.['Status'] === 'Enabled', 'AccessLogsBucket has versioning enabled')

const publicAccess = bucket?.Properties?.['PublicAccessBlockConfiguration'] as Record<string, boolean> | undefined
assert(
  publicAccess?.['BlockPublicAcls'] === true && publicAccess?.['BlockPublicPolicy'] === true &&
  publicAccess?.['IgnorePublicAcls'] === true && publicAccess?.['RestrictPublicBuckets'] === true,
  'AccessLogsBucket blocks all public access'
)

assert((Resources['AccessLogsBucketPolicy'] as Record<string, unknown>)?.['Condition'] === 'IsNotDevelopment', 'AccessLogsBucketPolicy is conditional on IsNotDevelopment')
assert((Resources['Alb5xxRateCanaryErrorAlarm'] as Record<string, unknown>)?.['Condition'] === 'UseCanaryDeployment', 'Alb5xxRateCanaryErrorAlarm is conditional on UseCanaryDeployment')

// --- Summary ---

if (failures.length > 0) {
  console.error(`\n${failures.length} assertion(s) failed:`)
  failures.forEach(f => console.error(f.replace(/[\r\n]+/g, ' ')))
  process.exit(1)
}

console.log(`\n✓ ${templatePath} passed all checks`)
