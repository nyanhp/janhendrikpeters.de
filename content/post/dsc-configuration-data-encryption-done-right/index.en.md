---
title: "Dsc Configuration Data Encryption Done Right"
date: 2020-01-17T00:00:00+02:00
draft: false
---

## DSC Configuration data encryption done right

So – you have gained some experience with Desired State Configuration and you have even encrypted credentials in your configurations through certificates. But how do you manage the credentials, and how are they integrated in your automated build process?

The open-source DSC Workshop (https://github.com/dsccommunity/dscworkshop) contains great resources to get you started. In this post, I would like to show you how to use the layering to define credentials at different layers, e.g. domain-wide or node-specific.

## The problem we try to solve

Imagine an environment that consists of multiple layers. Settings that are meant for the entire forest, settings for each individual domain that could overwrite forest settings, settings for different locations and at some point settings for one individual node.

These settings thus range from least-specific to most-specific. The more specific it gets, the more overwrites there might be. These settings do not only include plain text values like the domain name, but also credentials. A domain join credential might be the same for 90% of your servers in a given domain. Yet there are some roles that use a different account in order to join servers to another organizational unit perhaps.

Now, you could provide all credentials during MOF compilation, but that is not ideal for automation purposes. If you are using a build system, you could store all credentials as secured build variables, but that is also not very comfortable. None of these methods can be used to overlay different credentials like I mentioned in the last paragraph.

## How we solve it

The configuration data conundrum is one that does not pertain to encrypted secrets only, but to all configuration data alike. For our intents and purposes the open source workshop content is an ideal starting point. In addition to the modules that are required in the PoC code, you also need the modules ProtectedData, which provides general encryption through open standards, and Datum.ProtectedData, which wraps around ProtectedData to automatically decrypt configuration data.

First of all determine how generic or specific your credentials need to be. Do you have a domain-wide account for all domain join operations? Perfect – stick it in a layer very low in the hierarchy like the environment. Role-specific credentials, e.g. a domain join account only for one team's IaaS workloads, are stored in their respective role. Individual credentials like a random local admin password can be stored at the node level.

For my example, I will be using a enterprise-wide domain join credential that is overruled by a role-specific credential.

## Encrypting credentials

There are multiple ways of encrypting credentials with PowerShell. Starting with PowerShell 5 you could use the Cryptographic Message Syntax with an RSA document encryption certificate, for example. Incidentally, these certificate types are used by DSC to encrypt credentials in MOF files. With the ProtectedData module, these capabilities are also available in older versions of Windows PowerShell. ProtectedData allows you to use RSA and ECDH certificates as well as the good old password to encrypt data. Both modules use synchronous encryption with AES and asynchronous encryption to calculate the encryption key.

Lucky for us, we don't need to be firm on public key cryptography (although it certainly doesn't hurt!) to get going.

```powershell
$credential = Get-Credential
$dbConnectionString = 'Server=MyHost\MyInstance;User=John;Password=OhGodWhy'
$encryptionKey = Read-Host -AsSecureString -Prompt 'Encryption key for configuration item'
$encCredential = $credential | Protect-Datum -Password $encryptionKey -MaxLineLength -1
$encConnectionString = $dbConnectionString | Protect-Datum -Password $encryptionKey -MaxLineLength -1

# Now the strings can be copied into your configuration
$encCredential | Set-Clipboard
$encConnectionString | Set-Clipboard
```

One caveat of course: All encrypted values should be of the correct data type. If your Domain deployment requires the SafeModeAdminPassword as a credential and not as a SecureString, adjust accordingly. Similarily, values like a database connection string are just plain strings.

Let's assume we have a simple setting in our ServerBaseline.yml, which is one of the first and thus most generic settings, which is called Domain, which contains settings like the domain name, but also the domain join credential.

```yaml
Domain:
  DomainFqdn : subdomain.environment01.com
  DomainName : subdomain
  DomainDN : DC=subdomain,DC=environment01,DC=com
  DomainJoinAccount : "[ENC=PE9ianMgVm  ...  PC9PYmpzPg==]"
```

The override might occur in FileServer.yml, because the File Services team wants to keep tabs on their account. Overriding this setting is extremely simple:

```yaml
Domain:
  DomainJoinAccount : "[ENC=PE9ianMgVm  ...  T2Jqcz4=]"
```

You can spot our credentials here – the encrypted data is encapsulated in square brackets and prefixed with the string “ENC=” so that Datum can automatically decrypt the data. Take care to also use double quotes around the square brackets.

When I say automatically, this if course means that you will have to accomplish one additional step. In order for Datum to properly decrypt the values at build time, you need to edit your Datum.yml.

The Datum control file should contain either the plain-text password (I can hear IT Security people gasping frantically for air here) or the certificate thumbprint of some document encryption certificate that you possess the private key of.

```yaml
DatumHandlers:
  Datum.ProtectedData::ProtectedDatum:
    CommandOptions:
      PlainTextPassword: DECRYPTIONKEY
```

While the plain-text password is of course bad, you could envision a scenario where a regex replace happens before the data is imported in your build. The file would of course still contain the plain-text password for a short time.

A certificate certainly improves things a bit, and offloads the security of your process to the security of your private key.

```yaml
DatumHandlers:
  Datum.ProtectedData::ProtectedDatum:
    CommandOptions:
      Certificate: E85FB79AA7FBE5301BD30AB0609AF282430C4871
```

The only thing that needs to be done now are the LCM settings. There are already plenty of articles available on MOF encryption, so we will not rehash them here. Get yourself a certificate for each node and add the thumbprint to the node-specific file. Now, not only are your configuration data files encrypted, but also the MOF files that are part of your build output.

With my customers, I usually use the following settings for my LCM role. Automatically determining the certificate to use means less friction but also means that you need to automate this to some degree.

```yaml
LCMConfig:
  Settings:
    RefreshMode: Pull
    RebootNodeIfNeeded: true
    ActionAfterReboot: ContinueConfiguration
    AllowModuleOverwrite: true
    ConfigurationMode: ApplyAndAutoCorrect
    ConfigurationModeFrequencyMins: 15
    CertificateID: '$((Get-ChildItem cert:\localmachine\my -DnsName $Node.Name | Sort NotBefore | Select -First 1).ThumbPrint)'
```

Each node needs to get both Thumbprint as well as the certificate file path assigned for the build to actually encrypt the credentials. The CertificateID property of the LCM settings of course is meant for the node, so that the node knows which certificate is used to decrypt.

And that wraps it up!
To sum up:

1. Adopt the DSC PoC from https://github.com/dsccommunity/dscworkshop
1. Determine the configuration data you need
1. Determine which parts of your configuration data need to be encrypted
1. Encrypt this data with either a password or a certificate
1. Ensure that each node has a document encryption certificate suitable for DSC to encrypt the MOF files on your build host


Here are some links to go further down the rabbit hole:

- Open Source DSC PoC/Workshop: <https://github.com/dsccommunity/dscworkshop>
- DSC: <https://learn.microsoft.com/en-us/powershell/scripting/dsc/overview/overview>
- MOF encryption: <https://learn.microsoft.com/en-us/powershell/scripting/dsc/pull-server/securemof>
