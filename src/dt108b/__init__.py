"""DT108B direct USB printing package."""

__version__ = "1.2.0"
__all__ = ["print_file", "diagnose"]


def print_file(*args, **kwargs):
    from .printer import print_file as implementation
    return implementation(*args, **kwargs)


def diagnose():
    from .diagnose import diagnose as implementation
    return implementation()
