﻿# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

Describe "Verify Markdown Links" {
    BeforeAll {
        # WARNING: Keep markdown-link-check pinned at 3.7.2 OR ELSE...
        start-nativeExecution { sudo npm install -g markdown-link-check@3.7.2 }

        # Cleanup jobs for reliability
        get-job | remove-job -force
    }

    AfterAll {
        # Cleanup jobs to leave the process the same
        get-job | remove-job -force
    }

    $groups = Get-ChildItem -Path "$PSScriptRoot\..\..\..\*.md" -Recurse | Group-Object -Property directory

    $jobs = @{}
    # start all link verification in parallel
    Write-Verbose -verbose "starting jobs for performance ..."
    Foreach($group in $groups)
    {
        $job = start-job {
            param([object] $group)
            foreach($file in $group.Group)
            {
                $results = markdown-link-check $file 2>&1
                Write-Output ([PSCustomObject]@{
                    file = $file
                    results = $results
                })
            }
        } -ArgumentList @($group)
        $jobs.add($group.name,$job)
    }

    # Get the results and verify
    foreach($key in $jobs.keys)
    {
        $job = $jobs.$key
        $results = Receive-Job -Job $job -Wait
        Remove-job -job $Job
        foreach($jobResult in $results)
        {
            $file = $jobResult.file
            $result = $jobResult.results
            Context "Verify links in $file" {
                # failures look like `[✖] https://someurl` (perhaps without the https://)
                # passes look like `[✓] https://someurl` (perhaps without the https://)
                $failures = $result -like '*[✖]*' | ForEach-Object { $_.Substring(4) }
                $passes = $result -like '*[✓]*' | ForEach-Object {
                    @{url=$_.Substring(4)}
                }
                $trueFailures = @()
                $verifyFailures = @()
                foreach ($failure in $failures) {
                    if($failure -like 'https://www.amazon.com*')
                    {
                        # In testing amazon links often failed when they are valid
                        # Verify manually
                        $verifyFailures += @{url = $failure}
                    }
                    else
                    {
                        $trueFailures += @{url = $failure}
                    }
                }

                # must have some code in the test for it to pass
                function noop {
                }

                if($passes)
                {
                    it "<url> should work" -TestCases $passes {
                        noop
                    }
                }

                if($trueFailures)
                {
                    it "<url> should work" -TestCases $trueFailures  {
                        if($url -match '^http(s)?:')
                        {
                            # If invoke-WebRequest can handle the URL, re-verify, with 5 retries
                            $null = Invoke-WebRequest -uri $url -RetryIntervalSec 2 -MaximumRetryCount 5
                        }
                        else {
                            throw "Tool reported Url as unreachable"
                        }
                    }
                }

                if($verifyFailures)
                {
                    it "<url> should work" -TestCases $verifyFailures -Pending  {
                    }
                }

                if(!$passes -and !$trueFailures -and !$verifyFailures)
                {
                    It "has no links" {
                        noop
                    }
                }
            }
        }
    }
}
