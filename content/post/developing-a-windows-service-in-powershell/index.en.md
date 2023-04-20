---
title: "Developing a Windows Service in PowerShell"
date: 2021-01-15T00:00:00+02:00
draft: false
---

## Developing a Windows service in PowerShell

I had an interesting question from a participant in one of my last workshops: Is it possible to develop a Windows service in PowerShell? As you all now, the Service cmdlets are easy to use, but of course they do not allow you to actually create a working service from scratch.

In order for us to be able to create a service from scratch we need to use C#. However, we do not need a full development environment, just PowerShell with the Add-Type cmdlet.

## What is a service?

On Windows, services are processes hosted by the service controller. A service must implement several methods that the service controller uses to interact with the service. For example, the methods OnStart and OnStop.

To do this in `C#`, we can create our own service class as an extension to the ServiceBase class. Your service will only properly work if you at least override OnStart and OnStop. This is easy enough to imagine: If you start your service manually or it is started automatically, there has to be some code that is executed.

Read more about this in the official documentation [here](https://learn.microsoft.com/en-us/dotnet/api/system.serviceprocess.servicebase?view=dotnet-plat-ext-7.0).

From experience I recommend that the methods you override from the base class like OnStart and OnStop finish as quickly as possible. So, what can you do if the service startup phase needs to do some long-running work?

In these cases, simply using a Timer might already be enough. A Timer fires an event whenever the timer elapses and could be used to run some long code either once or every couple of time slots.

If you really only need some preparation task whenever the service starts, maybe use a Thread instead! Without getting into too much detail, this is also an excellent option to work in the background.

## The final code

The following complete code sample is a template which you can implement yourself. Both OnStart and OnStop are overridden and call the Start and Stop methods. Place your code inside these methods if you already have some experience writing C# code.

If you have never done anything in C#, you can use the OnStart and OnStop parameters to pass a script file. As you can see in the C# code, we instantiate a new PowerShell runspace, and just run the script. Be aware that this script needs to be able to run on its own. If you need a more complex solution, please use Visual Studio and properly develop your code with proper tools.

```powershell
param
(
    [string]
    $ServiceName = 'InfraSvc',

    [string]
    $OutPath = $pwd.Path,

    [string]
    $OnStart,

    [string]
    $OnStop,

    [switch]
    $Register
)

$binPath = (Join-Path -Path $OutPath -ChildPath "$ServiceName.exe")
if (Test-Path -Path $binPath)
{
    Remove-Item -Path $binPath
}

Add-Type -TypeDefinition @"
using System;
using System.ServiceProcess;
using System.Management.Automation;

public static class HostProgram
{
    #region Nested classes to support running as service
    public const string ServiceName = "$ServiceName";

    public class Service : ServiceBase
    {
        public Service()
        {
            ServiceName = HostProgram.ServiceName;
        }

        protected override void OnStart(string[] args)
        {
            HostProgram.Start(args);
        }

        protected override void OnStop()
        {
            HostProgram.Stop();
        }
    }
    #endregion

    static void Main(string[] args)
    {
        if (!Environment.UserInteractive)
            // running as service
            using (var service = new Service())
                ServiceBase.Run(service);
        else
        {
            // running as console app
            Start(args);

            Console.WriteLine("Press any key to stop...");
            Console.ReadKey(true);

            Stop();
        }
    }

    private static void Start(string[] args)
    {
        // service startup code here
        string onStart = @"$OnStart";

        if (string.IsNullOrWhiteSpace(onStart)) return;
        using (var psh = PowerShell.Create())
        {
            psh.AddScript((System.IO.File.ReadAllText(onStart)));
            psh.Invoke();
        }
    }

    private static void Stop()
    {
        // service startup code here
        string onStop = @"$OnStop";

        if (string.IsNullOrWhiteSpace(onStop)) return;
        using (var psh = PowerShell.Create())
        {
            psh.AddScript((System.IO.File.ReadAllText(onStop)));
            psh.Invoke();
        }
    }
}
"@ -OutputAssembly $binPath -ReferencedAssemblies System.ServiceProcess, System.Management.Automation

if ($Register.IsPresent)
{
    New-Service -Name $ServiceName -BinaryPathName $binPath -StartupType Automatic
}
```
