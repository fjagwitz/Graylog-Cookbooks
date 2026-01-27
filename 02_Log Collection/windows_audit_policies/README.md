### Windows Audit Policy Collection

This Section contains preconfigured Audit Policies that have been created along the Microsoft Audit Policy Recommendations. Microsoft makes a difference between Auditing Domain Controllers and Domain Member Servers, as these require different Audit Settings. You will find Policies excluding/including Global Object Access Auditing (GOAA), as activating this functionality requires some consideration in Advance. 

**What to consider when linking Auditing GPOs:**
- Domain Controller Audit Policies should be linked with the Domain Controllers OU to properly control the Scope of the Audit Settings
- Domain Member Server Audit Policies should be linked with one or more OUs being configured for hosting your System's machine accounts

**What to consider when activating Global Object Access Auditing:**
- Global Object Access Auditing can create large amounts of logs; this can impact your System's availability
- The high amount of logs might overwhelm your Log Management System in case you are not prepared

Links: 
- Microsoft Security Baselines Introduction: https://learn.microsoft.com/en-us/windows/security/operating-system-security/device-management/windows-security-configuration-framework/windows-security-baselines
- Microsoft Audit Policy Recommendations: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/security-best-practices/audit-policy-recommendations
- Best Practices regarding Advanced Audit Policy: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/security-best-practices/advanced-audit-policy-configuration
- Microsoft Security Baselines Blog: https://techcommunity.microsoft.com/category/security-baselines/blog/microsoft-security-baselines
- Security Compliance Toolkit: https://www.microsoft.com/en-us/download/details.aspx?id=55319
- File Auditing: https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/audit-file-system
- Registry Auditing: https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/audit-registry