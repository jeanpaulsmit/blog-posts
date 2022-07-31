using Pulumi;
using Pulumi.Azure.Core;
using Pulumi.Azure.Storage;
using KV = Pulumi.Azure.KeyVault;
using Pulumi.Azure.KeyVault.Inputs;
using Pulumi.Azure.ApiManagement;
using Pulumi.Azure.ApiManagement.Inputs;
using Pulumi.Azure.AppInsights;
using System;

class DeploymentStack : Stack
{
    public DeploymentStack()
    {
        // Define variables
        var config = new Pulumi.Config();
        var rgName = string.Format("{0}-{1}-{2}-{3}", config.Require("prefix"), config.Require("resourceFunction"), config.Require("environment"), config.Require("azureRegion"));
        var storageAccountName = string.Format("{0}{1}sa{2}{3}", config.Require("prefix"), config.Require("resourceFunction"), config.Require("environment"), config.Require("azureRegion"));
        var apimName = string.Format("{0}-{1}-{2}-{3}", config.Require("prefix"), config.Require("resourceFunction"), config.Require("environment"), config.Require("azureRegion"));
        var kvName = string.Format("{0}-{1}-kv-{2}-{3}", config.Require("prefix"), config.Require("resourceFunction"), config.Require("environment"), config.Require("azureRegion"));
        var appInsightsName = string.Format("{0}-{1}-appinsights-{2}-{3}", config.Require("prefix"), config.Require("resourceFunction"), config.Require("environment"), config.Require("azureRegion"));
        var tags = new InputMap<string>()
        {
            {"belongsto", "Core Resources"},
            {"environment", "Development"},
            {"costcenter", "Backend"},
            {"owner", "IT"}
        };

        // Get current identity details
        var clientConfig = Output.Create(Pulumi.Azure.Core.Invokes.GetClientConfig());
        var tenantId = clientConfig.Apply(c => c.TenantId);
        var currentPrincipal = clientConfig.Apply(c => c.ObjectId);

        // Create the Azure Resource Group
        var rg = new ResourceGroup("rg", new ResourceGroupArgs()
        {
            Name = rgName,
            Location = config.Require("azureLocation"),
            Tags = tags
        });

        // Create the storage account to contain policy, OpenApi and other deployment related files
        var sa = new Account("sa", new AccountArgs
        {
            ResourceGroupName = rg.Name,
            Name = storageAccountName,
            AccountKind = "StorageV2",
            AccountReplicationType = "LRS",
            AccountTier = "Standard",
            EnableHttpsTrafficOnly = true,
            Tags = tags
        },
        new CustomResourceOptions()
        {
            DependsOn = { rg }
        });
        var saContainerApim = new Container("apim-files", 
                              new ContainerArgs() { StorageAccountName = sa.Name, ContainerAccessType = "private"},
                              new CustomResourceOptions() { DependsOn = { rg } });

        var saContainerApi = new Container("api-files",
                             new ContainerArgs() { StorageAccountName = sa.Name, ContainerAccessType = "private"},
                             new CustomResourceOptions() { DependsOn = { rg } });

        // Create key vault to contain the certificate secret
        var kv = new KV.KeyVault("kv", new KV.KeyVaultArgs()
        {
            Name = kvName,
            ResourceGroupName = rg.Name,
            EnabledForDiskEncryption = false,
            SkuName = "standard",
            TenantId = tenantId,
            AccessPolicies =
            {
                new KeyVaultAccessPoliciesArgs
                {
                    TenantId = tenantId,
                    ObjectId = currentPrincipal,
                    SecretPermissions = {"get"},
                    CertificatePermissions = {"delete", "create", "get", "import", "list", "update"},
                }
            },
            Tags = tags
        });

        // Upload the certificate to Key Vault --> Currently disabled because no valid pfx which breaks the deployment
        // var pfxBytes = System.IO.File.ReadAllBytes("certificates/"+ config.Require("customDomainsCertificateName"));
        // var cert = new KV.Certificate("apim-tls-certificate", new KV.CertificateArgs()
        // {
        //     Name = "apim-tls-certificate",
        //     KeyVaultId = kv.Id,
        //     KeyVaultCertificate = new CertificateCertificateArgs()
        //     {
        //         Contents = System.Convert.ToBase64String(pfxBytes),
        //         Password = config.Require("customDomainsCertificatePasword")
        //     },
        //     CertificatePolicy = new CertificateCertificatePolicyArgs()
        //     {
        //         IssuerParameters = new CertificateCertificatePolicyIssuerParametersArgs()
        //         {
        //             Name = config.Require("customDomainsCertificateIssuer")
        //         },
        //         KeyProperties = new CertificateCertificatePolicyKeyPropertiesArgs()
        //         {
        //             Exportable = true,
        //             KeySize = 2048,
        //             KeyType = "RSA",
        //             ReuseKey = false
        //         },
        //         SecretProperties = new CertificateCertificatePolicySecretPropertiesArgs()
        //         {
        //             ContentType = "application/x-pkcs12"
        //         }
        //     }
        // },
        // new CustomResourceOptions()
        // {
        //     DependsOn = { rg, kv }
        // });

        // APIM resource
        var apim = new Service("apim", new ServiceArgs()
        {
            Name = apimName,
            ResourceGroupName = rg.Name,
            SkuName = "Developer_1",
            PublisherEmail = config.Require("publisherEmail"),
            PublisherName = config.Require("publisherName"),
            Tags = tags,
            Identity = new ServiceIdentityArgs()
            {
                Type = "SystemAssigned"
            }
        },
        new CustomResourceOptions()
        {
            CustomTimeouts = new CustomTimeouts { Create = TimeSpan.FromMinutes(60) },
            DependsOn = { rg, sa, kv  }
        });

        // Change Key Vault policy to be able to have APIM access the certificate
        // var kvApimPolicy = new KV.AccessPolicy("apim-policy", new KV.AccessPolicyArgs()
        // {
        //     TenantId = tenantId,
        //     ObjectId = apim.Identity.PrincipalId,
        //     SecretPermissions = {"get"},
        //     CertificatePermissions = {"get", "list"},
        //     KeyVaultId = kv.Id
        // });

        // Set custom domain
        // Call Powershell to assign custom domain to APIM instance

        // Create product on APIM
        var apimProduct = new Product("apimProduct", new ProductArgs()
        {
            ResourceGroupName = rg.Name,
            ApiManagementName = apim.Name,
            DisplayName = config.Require("productName"),
            ProductId = config.Require("productId"),
            ApprovalRequired = bool.Parse(config.Require("productApprovalRequired")),
            Published = bool.Parse(config.Require("productPublished")),
            SubscriptionRequired = bool.Parse(config.Require("productSubscriptionRequired")),
            SubscriptionsLimit = int.Parse(config.Require("productSubscriptionLimit"))
        },
        new CustomResourceOptions()
        {
            DependsOn = { apim }
        });
        var apimProductPolicy = new ProductPolicy("apimProductPolicy", new ProductPolicyArgs()
        {
            ResourceGroupName = rg.Name,
            ApiManagementName = apim.Name,
            ProductId = config.Require("productId"),
            XmlContent = @"<policies>
                            <inbound>
                                <base />
                            </inbound>
                            <backend>
                                <base />
                            </backend>
                            <outbound>
                                <set-header name='Server' exists-action='delete' />
                                <set-header name='X-Powered-By' exists-action='delete' />
                                <set-header name='X-AspNet-Version' exists-action='delete' />
                                <base />
                            </outbound>
                            <on-error>
                                <base />
                            </on-error>
                        </policies>"
        },
        new CustomResourceOptions()
        {
            DependsOn = { apim, apimProduct }
        });

        // Create user
        var apimUser = new User("user", new UserArgs()
        {
            ResourceGroupName = rg.Name,
            ApiManagementName = apim.Name,
            UserId = string.Format("{0}-user", config.Require("productId")),
            Email = string.Format("{0}-{1}@yourcompany.nl", config.Require("productId"), config.Require("environment")),
            FirstName = "user",
            LastName = config.Require("productName"),
            State = "active"
        },
        new CustomResourceOptions()
        {
            DependsOn = { apim }
        });

        // Create subscription
        var apimSubscription = new Subscription("subscription", new SubscriptionArgs()
        {
            ResourceGroupName = rg.Name,
            ApiManagementName = apim.Name,
            DisplayName = "Some subscription",
            ProductId = apimProduct.Id,
            UserId = apimUser.Id,
            PrimaryKey = config.Require("productSubscriptionKey")
        },
        new CustomResourceOptions()
        {
            DependsOn = { apim, apimProduct, apimUser }
        });

        // Create Application Insights
        var appInsights = new Insights("appinsights", new InsightsArgs()
        {
            Name = appInsightsName,
            ResourceGroupName = rg.Name,
            ApplicationType = "web",
            Tags = tags
        });
        // Create APIM diagnostics logger
        var apimLogger = new Logger("apimLogger", new LoggerArgs()
        {
            Name = $"{apimName}-logger",
            ResourceGroupName = rg.Name,
            ApiManagementName = apim.Name,
            ApplicationInsights = new LoggerApplicationInsightsArgs()
            {
                InstrumentationKey = appInsights.InstrumentationKey
            }
        },
        new CustomResourceOptions()
        {
            DependsOn = { appInsights, apim }
        });

        // Add health probe to APIM, create operation, policy and assign to product
        var apiHealthProbe = new Api("healthProbe", new ApiArgs()
        {
            ResourceGroupName = rg.Name,
            ApiManagementName = apim.Name,
            DisplayName = "Health probe",
            Path = "health-probe",
            Protocols = "https",
            Revision = "1"
        },
        new CustomResourceOptions()
        {
            DependsOn = { apim }
        });
        var apimHealthProbeOperation = new ApiOperation("pingOperation", new ApiOperationArgs()
        {
            ResourceGroupName = rg.Name,
            ApiManagementName = apim.Name,
            ApiName = apiHealthProbe.Name,
            DisplayName = "Ping",
            Method = "GET",
            UrlTemplate = "/",
            OperationId = "get-ping"
        },
        new CustomResourceOptions()
        {
            DependsOn = { apiHealthProbe }
        });
        var apiHealthProbePolicy = new ApiPolicy("healthProbePolicy", new ApiPolicyArgs()
        {
            ResourceGroupName = rg.Name,
            ApiManagementName = apim.Name,
            ApiName = apiHealthProbe.Name,
            XmlContent = @"<policies>
                            <inbound>
                                <return-response>
                                    <set-status code='200' />
                                </return-response>
                                <base />
                            </inbound>
                        </policies>"
        },
        new CustomResourceOptions()
        {
            DependsOn = { apimHealthProbeOperation }
        });
        var apiHealtProbeProduct = new ProductApi("healthProbeProduct", new ProductApiArgs()
        {
            ResourceGroupName = rg.Name,
            ApiManagementName = apim.Name,
            ApiName = apiHealthProbe.Name,
            ProductId = apimProduct.ProductId
        },
        new CustomResourceOptions()
        {
            DependsOn = { apim, apimProduct, apiHealthProbePolicy }
        });
    }
}
