"""Tests for runner module."""

import sys
import os
import json
import unittest
from unittest.mock import patch, MagicMock, mock_open

# Add parent lib directory to path
sys.path.insert(0, '/home/tommasop/code/ai/acts-spec/.acts/lib')

from runner import OperationRunner, HAS_YAML


class TestOperationRunner(unittest.TestCase):
    """Test cases for OperationRunner."""

    def setUp(self):
        """Set up test fixtures."""
        self.test_acts_dir = '/tmp/test_acts'
        os.makedirs(self.test_acts_dir, exist_ok=True)
        os.makedirs(os.path.join(self.test_acts_dir, 'operations'), exist_ok=True)

    def tearDown(self):
        """Clean up test fixtures."""
        import shutil
        if os.path.exists(self.test_acts_dir):
            shutil.rmtree(self.test_acts_dir)

    @patch('runner.OperationRunner._find_acts_dir')
    def test_init(self, mock_find):
        """Test runner initialization."""
        mock_find.return_value = self.test_acts_dir
        runner = OperationRunner(verbose=True)
        self.assertTrue(runner.verbose)
        self.assertEqual(runner.acts_dir, self.test_acts_dir)
        self.assertIsNotNone(runner.validator)

    @patch('os.getcwd')
    @patch('os.path.isdir')
    def test_find_acts_dir_found(self, mock_isdir, mock_getcwd):
        """Test finding .acts directory."""
        mock_getcwd.return_value = '/home/user/project'

        def isdir_side_effect(path):
            return path == '/home/user/project/.acts'

        mock_isdir.side_effect = isdir_side_effect

        runner = OperationRunner.__new__(OperationRunner)
        acts_dir = runner._find_acts_dir()
        self.assertEqual(acts_dir, '/home/user/project/.acts')

    @patch('os.getcwd')
    @patch('os.path.isdir')
    def test_find_acts_dir_not_found(self, mock_isdir, mock_getcwd):
        """Test error when .acts directory not found."""
        mock_getcwd.return_value = '/home/user/project'
        mock_isdir.return_value = False

        runner = OperationRunner.__new__(OperationRunner)
        with self.assertRaises(RuntimeError) as cm:
            runner._find_acts_dir()
        self.assertIn('Could not find .acts directory', str(cm.exception))

    def test_parse_operation_not_found(self):
        """Test error when operation not found."""
        with patch.object(OperationRunner, '_find_acts_dir', return_value=self.test_acts_dir):
            runner = OperationRunner()
            with self.assertRaises(RuntimeError) as cm:
                runner._parse_operation('nonexistent')
            self.assertIn('Operation not found', str(cm.exception))

    def test_parse_operation_no_frontmatter(self):
        """Test parsing operation without frontmatter."""
        op_path = os.path.join(self.test_acts_dir, 'operations', 'test-op.md')
        with open(op_path, 'w') as f:
            f.write('# Operation\n\nSome content.')

        with patch.object(OperationRunner, '_find_acts_dir', return_value=self.test_acts_dir):
            runner = OperationRunner()
            result = runner._parse_operation('test-op')
            self.assertEqual(result, {})

    @unittest.skipUnless(HAS_YAML, "PyYAML not installed")
    def test_parse_operation_with_yaml_frontmatter(self):
        """Test parsing operation with YAML frontmatter."""
        op_path = os.path.join(self.test_acts_dir, 'operations', 'test-op.md')
        with open(op_path, 'w') as f:
            f.write('---\nname: Test Operation\nversion: 1.0\n---\n\n# Content')

        with patch.object(OperationRunner, '_find_acts_dir', return_value=self.test_acts_dir):
            runner = OperationRunner()
            result = runner._parse_operation('test-op')
            self.assertEqual(result['name'], 'Test Operation')
            self.assertEqual(result['version'], 1.0)

    def test_find_executable_file(self):
        """Test finding executable file."""
        exec_path = os.path.join(self.test_acts_dir, 'operations', 'test-op')
        with open(exec_path, 'w') as f:
            f.write('#!/bin/bash\necho "test"')
        os.chmod(exec_path, 0o755)

        with patch.object(OperationRunner, '_find_acts_dir', return_value=self.test_acts_dir):
            runner = OperationRunner()
            found = runner._find_executable('test-op')
            self.assertEqual(found, exec_path)

    def test_find_executable_fallback_to_md(self):
        """Test fallback to markdown file."""
        md_path = os.path.join(self.test_acts_dir, 'operations', 'test-op.md')
        with open(md_path, 'w') as f:
            f.write('# Operation')

        with patch.object(OperationRunner, '_find_acts_dir', return_value=self.test_acts_dir):
            runner = OperationRunner()
            found = runner._find_executable('test-op')
            self.assertEqual(found, md_path)

    def test_find_executable_not_found(self):
        """Test error when executable not found."""
        with patch.object(OperationRunner, '_find_acts_dir', return_value=self.test_acts_dir):
            runner = OperationRunner()
            with self.assertRaises(RuntimeError) as cm:
                runner._find_executable('nonexistent')
            self.assertIn('No executable found', str(cm.exception))

    @patch('subprocess.Popen')
    def test_execute_success(self, mock_popen_class):
        """Test successful execution."""
        mock_proc = MagicMock()
        mock_proc.returncode = 0
        mock_proc.communicate.return_value = (
            json.dumps({'status': 'success', 'result': 'ok'}),
            ''
        )
        mock_popen_class.return_value = mock_proc

        with patch.object(OperationRunner, '_find_acts_dir', return_value=self.test_acts_dir):
            runner = OperationRunner()
            result = runner._execute(
                '/path/to/exec',
                {'operation_id': 'test-op'},
                {}
            )

        self.assertEqual(result['status'], 'success')
        self.assertEqual(result['result'], 'ok')
        self.assertEqual(result['exit_code'], 0)

    @patch('subprocess.Popen')
    def test_execute_invalid_json_output(self, mock_popen_class):
        """Test handling of invalid JSON output."""
        mock_proc = MagicMock()
        mock_proc.returncode = 0
        mock_proc.communicate.return_value = ('not valid json', '')
        mock_popen_class.return_value = mock_proc

        with patch.object(OperationRunner, '_find_acts_dir', return_value=self.test_acts_dir):
            runner = OperationRunner()
            result = runner._execute(
                '/path/to/exec',
                {'operation_id': 'test-op'},
                {}
            )

        self.assertEqual(result['status'], 'error')
        self.assertIn('Invalid JSON output', result['error'])
        self.assertEqual(result['raw_output'], 'not valid json')

    @patch('runner.SchemaValidator')
    def test_run_validates_input(self, mock_validator_class):
        """Test that run validates input."""
        mock_validator = MagicMock()
        mock_validator.validate_input.return_value = False
        mock_validator_class.return_value = mock_validator

        # Create operation file
        op_path = os.path.join(self.test_acts_dir, 'operations', 'test-op.md')
        with open(op_path, 'w') as f:
            f.write('# Test')

        with patch.object(OperationRunner, '_find_acts_dir', return_value=self.test_acts_dir):
            runner = OperationRunner()
            result = runner.run('test-op', {}, dry_run=False)

        self.assertEqual(result['status'], 'error')
        self.assertIn('Input validation failed', result['error'])

    @patch('runner.SchemaValidator')
    @patch.object(OperationRunner, '_find_executable')
    @patch.object(OperationRunner, '_execute')
    def test_run_validates_output(
        self, mock_execute, mock_find_exec, mock_validator_class
    ):
        """Test that run validates output."""
        mock_validator = MagicMock()
        mock_validator.validate_input.return_value = True
        mock_validator.validate_output.return_value = True
        mock_validator_class.return_value = mock_validator

        mock_find_exec.return_value = '/path/to/exec'
        mock_execute.return_value = {'status': 'success'}

        # Create operation file
        op_path = os.path.join(self.test_acts_dir, 'operations', 'test-op.md')
        with open(op_path, 'w') as f:
            f.write('# Test')

        with patch.object(OperationRunner, '_find_acts_dir', return_value=self.test_acts_dir):
            runner = OperationRunner()
            runner.run('test-op', {}, dry_run=False)

        mock_validator.validate_output.assert_called_once_with('test-op', {'status': 'success'})

    def test_run_dry_run(self):
        """Test dry run mode."""
        # Create operation file
        op_path = os.path.join(self.test_acts_dir, 'operations', 'test-op.md')
        with open(op_path, 'w') as f:
            f.write('# Test')

        with patch.object(OperationRunner, '_find_acts_dir', return_value=self.test_acts_dir):
            runner = OperationRunner()
            result = runner.run('test-op', {'inputs': {'key': 'val'}}, dry_run=True)

        self.assertEqual(result['status'], 'dry_run')
        self.assertEqual(result['operation_id'], 'test-op')
        self.assertIn('invocation_input', result)
        self.assertEqual(result['invocation_input']['operation_id'], 'test-op')


if __name__ == '__main__':
    unittest.main()
