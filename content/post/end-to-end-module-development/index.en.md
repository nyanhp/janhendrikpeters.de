---
title: "End to End Module Development"
date: 2023-02-23T00:00:00+02:00
draft: false
tags:
  - pwsh
  - development
  - ci-cd
  - pester
  - psmoduledevelopment
categories:
  - dev
---

# End to end module development

## Why are we here?
So, everybody is talking about DevOps, CI/CD, Pester, git, Visual Studio Code and so on. But what's it to you? A customer recently reminded me that there are little end to end module build and release howto's that assume little and help you get up to speed.

In this post, we'll try to cover a lot of ground. None of the topics will be deep-dived into as every topic is documented very well online.

Quick warning: I might add some images in the future to break this long post up ever so slightly.

Prerequisites to follow along:

- You have developed PowerShell functions or a PowerShell module before
  - If not, head on over to https://microsoft.com/powershell and learn about the basics
- Internet access to download the required tools
  - If later on you develop in an air-gapped environment, you will learn how to setup distribution here as well
- That's it.

Aim of this guide:

- You'll end up with a module built and packaged for easy distribution
- You'll create the necessary automation to do the build, packaging and distribution
- You'll be able to deploy the full required infrastructure on-premises or using SaaS services

## Preparing the development workstation

In my opinion, developing PowerShell modules without a good development environment is certainly not ideal. For its ease of use, versatility and for the fact that it is free and open-source, I recommend installing [Visual Studio Code](https://code.visualstudio.com).

To be able to develop PowerShell more effectively, install the PowerShell Extension as well.

Lastly, to work with git as a source code management tool, install git from <https://git-scm.org>. The default settings are usually fine.

Of course, nowadays with technologies like GitHub Code Spaces, you don't even need to think about development environments any longer. However, this guide is also meant to elevate code development in air-gapped environments to the next level.

One last recommendation before starting with module development or publishing is to download the most recent version of the modules `PackageManagement` and `PowerShellGet`.

## Preparing a disconnected environment

Occasionally, development work is done in a disconnected scenario with no direct or proxied internet access. This of course is not ideal if we want to install additional modules.

Traditionally, most enterprise customers of mine have some form of software distribution system already which is well-suited for distributing not only VS Code, git and the PowerShell-Extension, but also PowerShell modules via simple file copies.

A more suitable solution for PowerShell packages is a so-called NuGet feed. You already know such a feed: <https://www.powershellgallery.com>. These feeds can be self-hosted with little work.

Free options (disregarding TCO) include:

- Local directory (only suitable for testing)
- CIFS/SMB share
  - easy to configure, albeit with no nice UIs on top
- ASP.NET page importing Nuget.Server: https://github.com/nuget/nuget.server
  - Still pretty easy to configure, Authentication via API key
  - Supports SSL/TLS
  - Have a look at https://github.com/AutomatedLab/AutomatedLab/tree/develop/LabSources/CustomRoles/NuGetServer for some automation pointers
- A full-fledged gallery like: https://github.com/nuget/NugetGallery
  - The best solution you can build and host yourself, moderate configuration

Among the paid options are for example Azure Artifacts, Inedo ProGet and more.

For a starter environment, let's keep it simple with a file share. Consider the following code:

```powershell
$shareDir = New-Item-ItemType Directory -Path D:\NugetInbox, D:\NugetOutbox
New-SmbShare-Path D:\NugetInbox -Name InternalPsGalleryPublish -FullAccess Administrators
New-SmbShare-Path D:\NugetOutbox -Name InternalPsGallery -ReadAccess Everyone
```

To later make use of the gallery, a registration is necessary:

```powershell
Register-PSGallery-SourceLocation \\TheServer\InternalPsGallery -PublishLocation \\TheServer\InternalPsGalleryPublish
```

We've configured two different paths to have some sort of review before moving packages over to the download section. You can also use the same directory of course and limit who can publish using SMB and NTFS ACLs.

Download the first bunch of modules from the public gallery and publish them locally if required!

We need:

- PSModuleDevelopment for Scaffolding
- Pester for Testing
- PackageManagement and PowerShellGet for publishing

```powershell
Save-Module-Repository PSGallery -Name PSModuleDevelopment, Pester, PackageManagement, PowerShellGet -Path .
Publish-Module-Repository Internal -Path .
```

## Project Scaffolding

As you've already had some experience with PowerShell module development you might already have some experience with module templates or scaffolding. For its ease of use and small footprint, this guide uses the module PSModuleDevelopment to kickstart the arduous process of creating new modules.

1. Open up Visual Studio Code and open the included terminal
1. Download the module if you did not do so earlier: `Install-Module -Name PSModuleDevelopment -Scope CurrentUser`
1. PSModuleDevelopment packages a bunch of templates, for most starter projects, MiniModule will already be more than enough: `Invoke-PSMDTemplate -TemplateName MiniModule -Name AutoModule -OutPath $home/source/repos -Parameters @{Description = 'This module is the bees knees'}`
1. The previous cmdlet scaffolded all you need. You can open the entire folder in Visual Studio Code and continue from there. `code $home/source/repos/AutoModule`

Friedrich, the creator of PSModuleDevelopment, has a huge library of other helpful modules, so at any point feel free to peruse his documentation at <https://psframework.org>. His module scaffolding templates are oriented at community best practices regarding structure, build process, testing and documentation.

Examine the contents of your new module. A folder called .github containing two fully functional workflows, a folder named like your module containing all code, a folder called build containing the build automation scripts to make your module independent of the tooling and a folder called tests containing a number of general Pester tests validating code quality for example. More on those later.

For now, it is time to include this repository in source code management.

## Source Code Management

Here is where it all starts. All our PowerShell source code belongs in source code management, even if it is just you alone who will create code. Why, you ask? Among the many benefits of a source control system are versioning and change tracking. You'll be able to easily roll back erroneous code and publish versioned releases with the help of a versioning system.

Source code management also helps with collaboration. In public and private projects alike, integrating changes from different developers can be complicated. Good source code management tools can solve this issue, or at the very least help you solve it.

This guide focuses on git as a source code management tool. It is the de-facto standard among developers all over the world. If you are interested in learning more about git than this post teaches you, the tutorials from Atlassian are brilliant and cover everything.

1. Open up Visual Studio Code and open the newly created module folder if you haven't yet done so.
1. In the built-in terminal, initialize the directory as a source code repository using git initFeel free to use the graphical UI, but I recommend you learn the most important git commands as well.
1. After the initialization, all changes inside the folder will already be tracked. You will notice that all files start out with a green letter U next to them, indicating that they are Untracked.
1. To prepare files for including them in source control, you need to stage them. The added benefit of staging is of course that you can compare changes to your staged files! git add .
1. After staging your files, they will now appear amber with an A next to them, indicating that they have been added to the staging area. git status
1. To seal the deal, we commit our changes. A commit is referenced by a unique hash value, and represents a snapshot of your repository contents at a point in time. `git commit -m “Initial commit”Commit messages should be short and to the point. Put yourself in the shoes of someone examining your code – they should be able to quickly see why a file was changed for example. Each commit should ideally only include one change at a time – notable exemption is an initial commit.
1. For now, our repository lives only on the local machine. However, all changes are now tracked.
1. Each change to your code is rinse-and-repeat: git add, git commit, git status

## Testing the module locally

Before publishing the code and the module, let's test it locally using the included build scripts. You can safely run the following three scripts in order:

1. ./build/vsts-prerequisites.ps1 is used to download prerequisites for your build process
1. Build dependencies are an important topic. There is a special module PSDepend which can be used to keep track of such dependencies and resolve them at build time if your project gets bigger.
1. ./build/vsts-validate.ps1 is used to test the module's functionality as well as code quality.
1. ./build/vsts-build.ps1 -LocalRepo -SkipPublish is used to build the module in a folder publish.
1. The build script is meant to be used in a pipeline, where the output it generates is also called build artefact.

Now that you've run both test and build, a couple of new files and folders have been created. These are generated fresh with every build and do not belong in source control. So, let's ignore them by adding a file called .gitignore:

`'publish','TestResults' | Add-Content-Path ./.gitignore`

The folders publish and TestResults should now appear grey and should not be part of your working directory any longer. You know the drill now: Stage and commit the recent change: git add .gitignore; git commit -m 'Add .gitignore'

At this point, you could very well run everything locally, with you being the build automation. Commonly though, PowerShell modules are tested, built and published using CI tools like GitHub Workflows or Azure Pipelines. CI stands for Continuous Integration and simply means: Code from different developers is continuously integrated into the mainline or production code. This is what we'll do next.

## Publishing your code

As a code hosting platform, GitHub is arguably the most popular one. It is free for individuals and teams alike, hosting private and public repositories. So, your next step is to sign up for GitHub if you like.

> GitHub is by far not the only tool. Take a look at self-hosted solutions like
> Azure DevOps Server, GitLab or gitea for example, as well as other SaaS
> solutions like Azure DevOps, Atlassian BitBucket or GitLab.
> All commonly used tools are very, very similar…

After creating your account, you can create your very first hosted repository. In case you are wondering about yet another tool: You can again use a simple file share to host your repository centrally and have other developers work with your shared code. All hosted repositories are nothing more than a folder initialized with git init --bare at their core. All the bells and whistles are added later on.

1. In your new repository, follow the instructions to add a remote and push your codeRemotes are destinations for your code. Typically the remote origin is used to push and pull the mainline code. Over time you will probably work with public repos and configure an additional remote called upstream for example
1. After pushing from VS Code, navigate back to your repo and select the button Actions.
The workflow that is already running was precreated by PSModuleDevelopment. Every commit in your main code triggers such a workflow run that will build and publish your module.

For now, the workflow will fail since we haven't created the encrypted variable containing the API key to the public PowerShell gallery.

Now that your repository is hosted at a central location, other developers can begin to contribute. This of course requires some additional steps yet again.

First of all, you and your team should decide on a branching strategy, that is: Where is my production code, and how are new features added to it? For the sake of simplicity, you can start with a trunk-based workflow. One main branch of code that developers continuously integrate their changes into, typically coming in from separate branches.

When you initalized your repository, an initial branch called master or main was already created for you. This will continue to be our starting point. New features branch off of this main branch and are later merged back into it. Again, Atlassian has one of the best tutorials on different branching strategies: <https://www.atlassian.com/git/tutorials/using-branches>

The key is to have all your developers use the same strategy in the shared project. Let's add a feature branch and try to merge it back.

1. git branch --list will show you the list of branches that are currently known locally
1. To create a new branch, use git branch feature/addAwesomeFunction for example.
1. To switch your working directory to that branch, you can use git switch feature/addAwesomeFunction.
1. In your new branch, add your first function Get-StuffDone to the module template. To do so, simply create a file called Get-StuffDone.ps1 in your module's functions folder.
1. You can also automate this again: Invoke-PSMDTemplate -TemplateName function -OutPath $home/source/repos/AutoModule/AutoModule/functions -Name Get-StuffDone
1. Inside that file, create a single function called Get-StuffDone and add some code. Or not.
1. Stage, commit and push your branch! By pushing the branch, you will publish it to your remote repo and others can see and work with it.Recent git versions enable the option to auto-create your remote branches. If you decided against this feature, use: git branch --set-upstream-to feature/addAwesomeFunction and then git push
1. Browse to your online repository, as our work continues there!

To safely integrate changes into the main code, many projects use Pull Requests or Merge Requests. A developer tells the repository maintainer that they've created some code and would like the owner to review and incorporate it. Usually, pull requests are validated to ensure that the code is tested and adheres to the projects guidelines.

Guess what? That's what you will do next. The MiniModule template already includes a validation workflow to test your changes. In your online repo, go to Pull Requests and click on New Pull Request. In the top left corner, select the main branch on the left side, which is the destination. On the right side, select your new feature branch and click on Create Pull Request. Fill in the details and click on Create again.

The validation process automatically starts. Using branch protection policies, you can further limit what project members can or cannot do. A required review is always a good idea, for example.

Once the validation is successful, you can merge your PR, thereby adding this code to the main, productive code.

In Visual Studio Code, switch back to your branch main and use git pull to download the latest changes. Use git branch pestertests now to prepare for what's next.

## Adding tests

You may have noticed that your code is already being tested. Now is a good time to expand upon that slightly. Many modules being released to the public gallery use Pester to validate that their code works, is of a decent quality and so on. Since you are using PSModuleDevelopment, code quality is pretty much covered. Friedrich has created a bunch of tests to validate if help content was created for example.

Adding your own tests can be a chore at the beginning, but it is totally worth it. The general idea is to employ both Unit as well as Integration tests if you can. Unit tests test a unit of code, for example a function, as a black box. Stuff goes in, stuff comes out. We need to test that if the right stuff goes in, the expected stuff goes out. That does not only include the expected input but also the unexpected or plain wrong. If a user passes wrong data, an exception should occur for example.

The word should is pretty central to your tests – Pester uses a little function called Should to compare our test results with the expectations!

If you wanted to add a unit test for your new function, you could create a file called tests\functions\Get-StuffDone.tests.ps1. With Pester's syntax, the test scaffolding will look like this to get you started:

```powershell
BeforeDiscovery {
  # Build your test data here, for example# Import your module, if requiredImport-Module$PSScriptRoot/../AutoModule -Force
}

Describe 'The test suite' {
  Context 'Get-StuffDone' {
    It 'When a goes in, b should come out' {
      Get-StuffDone a | Should -Be'b'
    }

    It 'When x goes in, it should throw an exception' {
      Get-StuffDone x -ErrorAction Stop | Should -Throw
    }
  }
}
```

Pester's syntax is deceptively simple. You will quickly notice however that things can get complicated. Just take it one step at a time and be proud that now your code has tests, other developers have an easier time integrating their work.

You know what comes next: Stage, Commit, Push, Create Pull Request, Merge.

## The final piece: Publish to a gallery

Up until now, everything could have been done on shared infrastructure unless you have very sensitive information in your repository (hint: you probably shouldn't…). At this final point however, you may want to look a little closer at your options.

With modules, a sensible last step is publishing the finished module to a gallery. If this is hosted on your own premises, your build system needs access to this environment. Solutions like GitHub Workflows allow you to self-host the build agents. In the case of GitHub, those are called Runners.

A runner can be any machine, really, but if you can, you should look at containerised solutions so that your builds can get a fresh agent every time that automatically gets destroyed after the build. Using machines that are permanently running is not a great choice, as builds can leave the system a mess.

To host a GitHub runner, head on over to your repo, and click on Settings. On the left-hand side, in the Actions menu, you can find the instructions how to add a runner to your repository. Enterprises rather host runners for multiple projects.

If your module is fit to be released to the gallery, you can add a GitHub Secret here as well. It should be called APIKEY and contain the key you got from <https://powershellgallery.com>. If you are using a different gallery, you will need to update your build scripts to reflect that as well.

Lastly, if you find yourself doing this kind of work more often, why not add your own PSModuleDevelopment Scaffolding for internal projects?

Further reading
Most of what the community does is driven by a few bright minds. First and foremost, have a look at the [Release Pipeline Whitepaper](https://learn.microsoft.com/en-us/powershell/dsc/further-reading/whitepapers?view=dsc-1.1#the-release-pipeline-model) by Michael Greene and Steven Murawski.

Matt Hitchcock also has an interesting take on this topic <https://github.com/matthitchcock/trust-the-rp/blob/master/trust-the-release-pipeline.md> with a focus on the trust a well-running pipeline can build.

To get more help by all the talented module builders, why not head over to <https://powershell.org> and register for the Discord or Slack?
