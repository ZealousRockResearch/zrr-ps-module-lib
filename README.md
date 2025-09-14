# ZRR PowerShell Module Library

Enterprise-grade PowerShell modules developed by Zealous Rock Research following industry best practices and PowerShell Gallery compliance standards.

## Repository Structure

```
zrr-ps-module-lib/
├── infrastructure/           # Infrastructure management modules
├── security/                # Security and compliance modules
├── research/                # Research-specific modules
│   └── ZRR.Research.EntrezUtilities/  # NCBI Entrez E-utilities wrapper
├── automation/              # General automation modules
├── utility/                 # Utility and helper modules
├── module-registry.json    # Module registry and metadata
└── scripts/                # Helper scripts and tools
```

## Featured Modules

### 🧬 ZRR.Research.EntrezUtilities v1.0.0

Enterprise-grade PowerShell module for accessing NCBI Entrez Programming Utilities (E-utilities).

**Key Features:**
- ✅ Complete E-utilities API coverage (ESearch, ESummary, EFetch)
- ✅ Enterprise logging with PSFramework integration
- ✅ Session management and batch processing
- ✅ Cross-platform compatibility (Windows/Linux/macOS)
- ✅ PowerShell Gallery compliance
- ✅ Comprehensive test coverage with CI/CD

**Quick Start:**
```powershell
Install-Module -Name ZRR.Research.EntrezUtilities -Repository PSGallery
Import-Module ZRR.Research.EntrezUtilities

# Search PubMed
Search-EntrezDatabase -Database pubmed -Term "cancer immunotherapy" -UseHistory

# Get document summaries
Get-EntrezDocumentSummary -Database pubmed -RetMax 100
```

[→ Full Documentation](research/ZRR.Research.EntrezUtilities/Docs/README.md)

## Standards & Quality

All modules in this library adhere to:

- **ZRR Enterprise Standards**: Consistent naming, logging, error handling
- **PowerShell Gallery Compliance**: Complete help documentation, parameter validation
- **Cross-Platform Support**: Compatible with PowerShell 5.1+ and PowerShell 7+
- **Security Best Practices**: No hardcoded secrets, approved patterns only
- **Comprehensive Testing**: >80% code coverage with Pester framework
- **CI/CD Integration**: Automated testing and publishing workflows

## Module Registry

See [module-registry.json](module-registry.json) for complete module catalog with:
- Module metadata and dependencies
- Feature descriptions and compatibility
- Quality metrics and testing status
- Publishing information

## Installation

### Individual Modules
```powershell
Install-Module -Name ZRR.Research.EntrezUtilities -Repository PSGallery
```

### Development Installation
```powershell
git clone https://github.com/zealous-rock-research/zrr-ps-module-lib.git
Import-Module ".\zrr-ps-module-lib\research\ZRR.Research.EntrezUtilities\ZRR.Research.EntrezUtilities.psd1"
```

## Contributing

1. Follow ZRR PowerShell module standards
2. Ensure >80% test coverage
3. Include comprehensive documentation
4. Validate cross-platform compatibility
5. Submit pull request with conventional commits

## Support

- **Documentation**: https://docs.zealousrock.dev/powershell/
- **Issues**: [GitHub Issues](https://github.com/zealous-rock-research/zrr-ps-module-lib/issues)
- **Discussions**: [GitHub Discussions](https://github.com/zealous-rock-research/zrr-ps-module-lib/discussions)

---

**Built with ❤️ by Zealous Rock Research**
*Enterprise-Ready • Cross-Platform • Production-Tested*