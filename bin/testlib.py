"""Shared pieces of the helper test suites (bin/<tool>_test.py). Not a helper itself."""
import importlib.machinery
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def load_helper(name):
    """The helper bin/<name> imported as a module."""
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), os.path.join(HERE, name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def script_launcher():
    """How a test starts a helper by its launcher lines: directly on POSIX; on Windows through
    Git for Windows' bash (found as codex-cli finds it), since Windows cannot start a script
    by its first line."""
    if os.name != "nt":
        return []
    bash = load_helper("codex-cli").git_bash()
    if not bash:
        raise RuntimeError("Git for Windows (bash.exe) not found; the helper tests need it on Windows")
    return [bash]
