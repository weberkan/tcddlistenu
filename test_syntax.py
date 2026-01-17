#!/usr/bin/env python3
"""Test script"""

from enum import Enum

class WagonType(str, Enum):
    EKONOMI = "EKONOMİ"
    BUSINESS = "BUSINESS"
    YATAKLI = "YATAKLI"
    ALL = "ALL"

print("Test başarılı")
