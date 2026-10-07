"""
Output module for disasm step.
"""

import json
import os
from pathlib import Path
from typing import Dict, Any, List


class OutputWriter:
    def __init__(self, output_dir, engine, func_detector, xrefs, labels, image, strings):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.engine = engine
        self.func_detector = func_detector
        self.xrefs = xrefs
        self.labels = labels
        self.image = image
        self.strings = strings

    def write_all(self, sections_to_disasm=None, verbose=False):
        """Write JSON files with disassembly results."""
        # Determine binary name
        binary_name = "unknown"
        if hasattr(self.image, 'filepath') and self.image.filepath:
            binary_name = os.path.basename(self.image.filepath)

        # Write functions.json as list of function objects
        functions_list = []
        for func in self.func_detector.functions.values():
            functions_list.append({
                "start": f"0x{func.start:08X}",
                "end": f"0x{func.end:08X}",
                "name": func.name,
                "section": func.section,
            })
        functions_path = self.output_dir / "functions.json"
        with open(functions_path, "w") as f:
            json.dump(functions_list, f, indent=2)

        # Write strings.json as list of dicts with address as hex string
        strings_list = []
        for s in self.strings:
            strings_list.append({
                "address": f"0x{s['address']:08X}",
                "string": s["string"],
                "length": s["length"],
            })
        strings_path = self.output_dir / "strings.json"
        with open(strings_path, "w") as f:
            json.dump(strings_list, f, indent=2)

        # Write labels.json as list of dicts {address: hex, name: str}
        labels_list = []
        for addr, label in self.labels._labels.items():
            labels_list.append({
                "address": f"0x{addr:08X}",
                "name": label.name,
            })
        labels_path = self.output_dir / "labels.json"
        with open(labels_path, "w") as f:
            json.dump(labels_list, f, indent=2)

        # Write xrefs.json as list of dicts with keys: type, from, to (hex strings)
        xrefs_list = []
        # Iterate over all XRefs in _from (or _to) to avoid duplicates? We'll use _from.
        for from_addr, xref_list in self.xrefs._from.items():
            for xref in xref_list:
                xrefs_list.append({
                    "type": xref.xref_type.value,
                    "from": f"0x{from_addr:08X}",
                    "to": f"0x{xref.to_addr:08X}",
                    "kernel_name": xref.kernel_name,
                })
        xrefs_path = self.output_dir / "xrefs.json"
        with open(xrefs_path, "w") as f:
            json.dump(xrefs_list, f, indent=2)

        # Write summary.json
        summary_path = self.output_dir / "summary.json"
        with open(summary_path, "w") as f:
            json.dump({
                "binary": binary_name,
                "total_instructions": sum(f.num_instructions for f in self.func_detector.functions.values()),
                "total_functions": len(self.func_detector.functions.values()),
            }, f, indent=2)

        if verbose:
            print(f"  Wrote disasm output to {self.output_dir}")

    def print_stats(self, engine, func_detector, xrefs, labels, strings, image):
        """Print statistics."""
        total_funcs = len(func_detector.functions.values())
        total_insns = sum(f.num_instructions for f in func_detector.functions.values())
        print(f"  Functions: {total_funcs}")
        print(f"  Instructions: {total_insns}")
        print(f"  Strings: {len(strings) if hasattr(strings, '__len__') else 0}")
        print(f"  Labels: {len(labels)}")
        print(f"  Xrefs: {sum(len(v) for v in xrefs.values())}")


def print_stats(engine, func_detector, xrefs, labels, strings, image):
    """Module-level print_stats for disasm.py."""
    total_funcs = len(func_detector.functions.values())
    total_insns = sum(f.num_instructions for f in func_detector.functions.values())
    print(f"  Functions: {total_funcs}")
    print(f"  Instructions: {total_insns}")
    print(f"  Strings: {len(strings) if hasattr(strings, '__len__') else 0}")
    print(f"  Labels: {len(labels)}")
    print(f"  Xrefs: {sum(len(v) for v in xrefs.values())}")


def write_summary(stats: Dict[str, Any], out_dir: str) -> str:
    """Write a placeholder summary file and return its path."""
    out_dir_path = Path(out_dir)
    out_dir_path.mkdir(parents=True, exist_ok=True)
    summary_path = out_dir_path / "summary.json"
    with open(summary_path, "w") as f:
        json.dump(stats, f, indent=2)
    return str(summary_path)


def generate_header(timestamp, git_revision, compiler, host, mode) -> str:
    """Generate a placeholder header comment."""
    return f"""/* Generated by NFSU2 Recompilation
 * Timestamp: {timestamp}
 * Git Revision: {git_revision}
 * Compiler: {compiler}
 * Host: {host}
 * Mode: {mode}
 */"""
