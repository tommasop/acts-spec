"""Operation execution engine."""

import os
import sys
import subprocess
import json
from datetime import datetime
from typing import Dict, Any, Optional

from schema import SchemaValidator

# Optional YAML dependency
try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False
    yaml = None


class OperationRunner:
    def __init__(self, verbose: bool = False) -> None:
        self.verbose = verbose
        self.acts_dir = self._find_acts_dir()
        self.validator = SchemaValidator(self.acts_dir)
    
    def _find_acts_dir(self) -> str:
        """Find .acts directory from current working directory."""
        cwd = os.getcwd()
        while cwd != '/':
            acts_dir = os.path.join(cwd, '.acts')
            if os.path.isdir(acts_dir):
                return acts_dir
            cwd = os.path.dirname(cwd)
        raise RuntimeError("Could not find .acts directory")
    
    def run(
        self,
        operation_id: str,
        input_data: Dict[str, Any],
        parent_operation: Optional[str] = None,
        dry_run: bool = False
    ) -> Dict[str, Any]:
        """Run an operation and return the result."""
        # Parse operation frontmatter
        op_def = self._parse_operation(operation_id)

        # Validate input against schema
        if not self.validator.validate_input(operation_id, input_data):
            return {
                'operation_id': operation_id,
                'status': 'error',
                'error': 'Input validation failed'
            }

        if self.verbose:
            print(f"Running operation: {operation_id}", file=sys.stderr)
            print(f"Definition: {op_def}", file=sys.stderr)

        # Build invocation input
        invocation_input = {
            'operation_id': operation_id,
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'caller': parent_operation,
            'inputs': input_data.get('inputs', {}),
            'context': {
                'acts_dir': self.acts_dir,
                'working_dir': os.getcwd()
            }
        }

        if dry_run:
            return {
                'operation_id': operation_id,
                'status': 'dry_run',
                'invocation_input': invocation_input
            }

        # Find operation executable
        executable = self._find_executable(operation_id)

        # Execute operation
        result = self._execute(executable, invocation_input, op_def)

        # Validate output against schema
        self.validator.validate_output(operation_id, result)

        return result
    
    def _parse_operation(self, operation_id: str) -> Dict[str, Any]:
        """Parse operation markdown frontmatter."""
        md_path = os.path.join(self.acts_dir, 'operations', f'{operation_id}.md')

        if not os.path.exists(md_path):
            raise RuntimeError(f"Operation not found: {operation_id}")

        with open(md_path, 'r') as f:
            content = f.read()

        # Parse YAML frontmatter
        if content.startswith('---'):
            parts = content.split('---', 2)
            if len(parts) >= 3:
                if not HAS_YAML:
                    raise RuntimeError("YAML support requires PyYAML: pip install pyyaml")
                return yaml.safe_load(parts[1])

        return {}
    
    def _find_executable(self, operation_id: str) -> str:
        """Find the operation executable."""
        # Check for executable file
        exec_path = os.path.join(self.acts_dir, 'operations', operation_id)
        if os.path.exists(exec_path) and os.access(exec_path, os.X_OK):
            return exec_path

        # Fallback: use the markdown file (for inline operations)
        md_path = os.path.join(self.acts_dir, 'operations', f'{operation_id}.md')
        if os.path.exists(md_path):
            return md_path

        raise RuntimeError(f"No executable found for operation: {operation_id}")
    
    def _execute(
        self,
        executable: str,
        input_data: Dict[str, Any],
        op_def: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Execute the operation and capture output."""
        # Prepare environment
        env = os.environ.copy()
        env['ACTS_OPERATION_ID'] = input_data['operation_id']
        env['ACTS_CALLER'] = input_data.get('caller', '') or ''

        # Run operation
        proc = subprocess.Popen(
            [executable],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            text=True
        )

        stdout, stderr = proc.communicate(input=json.dumps(input_data))

        if self.verbose:
            print(f"stderr: {stderr}", file=sys.stderr)

        # Parse output
        try:
            result = json.loads(stdout)
        except json.JSONDecodeError:
            result = {
                'operation_id': input_data['operation_id'],
                'status': 'error',
                'error': 'Invalid JSON output',
                'raw_output': stdout
            }

        # Add exit code info
        result['exit_code'] = proc.returncode

        return result
