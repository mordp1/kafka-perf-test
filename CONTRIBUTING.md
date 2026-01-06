# Contributing to Kafka Performance Testing Suite

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## 🚀 Quick Start

1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/kafka-perf-test.git`
3. Create a branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test your changes
6. Commit: `git commit -m "Add: your feature description"`
7. Push: `git push origin feature/your-feature-name`
8. Create a Pull Request

## 📋 Contribution Guidelines

### Code Style

**Bash Scripts:**
- Use 4 spaces for indentation
- Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- Add comments for complex logic
- Use meaningful variable names

**Python:**
- Follow PEP 8 style guide
- Use type hints
- Add docstrings for functions and classes
- Keep functions focused and small

### Commit Messages

Use clear, descriptive commit messages:

```
Add: New feature description
Fix: Bug fix description
Update: Changes to existing feature
Docs: Documentation updates
Refactor: Code restructuring
Test: Test additions or modifications
```

### Testing

Before submitting:

1. Test with a local Kafka cluster
2. Verify HTML reports generate correctly
3. Check both producer and consumer tests work
4. Test with different configurations (TLS, SASL if possible)

### What to Contribute

We welcome:

- 🐛 Bug fixes
- ✨ New features (chart types, metrics, etc.)
- 📚 Documentation improvements
- 🎨 UI/Report enhancements
- 🔧 Configuration templates
- 📊 Additional chart types
- 🧪 Test coverage improvements

### Pull Request Process

1. Update README.md if adding features
2. Add documentation for new configuration options
3. Ensure scripts remain backward compatible
4. Test on both macOS and Linux if possible
5. Update CHANGELOG.md (if exists)

## 🤝 Code of Conduct

- Be respectful and constructive
- Welcome newcomers
- Focus on what's best for the community
- Show empathy towards other community members

## 📝 License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

## 💬 Questions?

Feel free to open an issue for:
- Feature requests
- Bug reports
- Questions about the code
- Suggestions for improvements

Thank you for contributing! 🎉
