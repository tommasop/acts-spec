"""CLI argument parsing and command dispatch."""

import argparse
import sys
import json
from runner import OperationRunner

def main():
    parser = argparse.ArgumentParser(
        prog='acts',
        description='ACTS Operation Invocation System'
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # run command
    run_parser = subparsers.add_parser('run', help='Run an operation')
    run_parser.add_argument('operation_id', help='Operation ID (e.g., task-review)')
    run_parser.add_argument('--parent-operation', help='ID of calling operation')
    run_parser.add_argument('--dry-run', action='store_true', help='Show what would be executed')
    run_parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    
    args = parser.parse_args()
    
    if args.command == 'run':
        return run_operation(args)
    else:
        parser.print_help()
        return 1

def run_operation(args):
    """Execute an operation."""
    runner = OperationRunner(verbose=args.verbose)
    
    # Build input from stdin
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        input_data = {}
    
    result = runner.run(
        operation_id=args.operation_id,
        input_data=input_data,
        parent_operation=args.parent_operation,
        dry_run=args.dry_run
    )
    
    # Output result to stdout
    json.dump(result, sys.stdout, indent=2)
    
    # Return exit code
    status = result.get('status', 'error')
    if status == 'success' or status == 'approved':
        return 0
    elif status == 'changes_requested':
        return 2
    else:
        return 1
