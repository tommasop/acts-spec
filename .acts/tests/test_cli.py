"""Tests for CLI module."""

import sys
import io
import json
import unittest
from unittest.mock import patch, MagicMock

# Add parent lib directory to path
sys.path.insert(0, '/home/tommasop/code/ai/acts-spec/.acts/lib')

from cli import main, run_operation


class TestCLI(unittest.TestCase):
    """Test cases for CLI module."""

    @patch('sys.argv', ['acts'])
    @patch('sys.stdout', new_callable=io.StringIO)
    def test_main_no_command_prints_help(self, mock_stdout):
        """Test that running without command prints help and exits with code 1."""
        exit_code = main()
        self.assertEqual(exit_code, 1)
        output = mock_stdout.getvalue()
        self.assertIn('usage:', output.lower())
        self.assertIn('acts', output.lower())

    @patch('sys.argv', ['acts', '--help'])
    @patch('sys.stdout', new_callable=io.StringIO)
    def test_main_help_flag(self, mock_stdout):
        """Test that --help flag prints usage information."""
        with self.assertRaises(SystemExit) as cm:
            main()
        self.assertEqual(cm.exception.code, 0)
        output = mock_stdout.getvalue()
        self.assertIn('usage:', output.lower())

    @patch('sys.argv', ['acts', 'run', '--help'])
    @patch('sys.stdout', new_callable=io.StringIO)
    def test_main_run_help_flag(self, mock_stdout):
        """Test that 'run --help' prints run command usage."""
        with self.assertRaises(SystemExit) as cm:
            main()
        self.assertEqual(cm.exception.code, 0)
        output = mock_stdout.getvalue()
        self.assertIn('operation_id', output)

    @patch('cli.OperationRunner')
    @patch('sys.stdin', io.StringIO('{}'))
    @patch('sys.stdout', new_callable=io.StringIO)
    def test_run_operation_success(self, mock_stdout, mock_runner_class):
        """Test successful operation execution."""
        # Setup mock runner
        mock_runner = MagicMock()
        mock_runner.run.return_value = {
            'operation_id': 'test-op',
            'status': 'success',
            'result': 'ok'
        }
        mock_runner_class.return_value = mock_runner

        # Create mock args
        args = MagicMock()
        args.operation_id = 'test-op'
        args.parent_operation = None
        args.dry_run = False
        args.verbose = False

        exit_code = run_operation(args)

        self.assertEqual(exit_code, 0)
        mock_runner.run.assert_called_once_with(
            operation_id='test-op',
            input_data={},
            parent_operation=None,
            dry_run=False
        )

        # Check output is valid JSON
        output = mock_stdout.getvalue()
        result = json.loads(output)
        self.assertEqual(result['status'], 'success')

    @patch('cli.OperationRunner')
    @patch('sys.stdin', io.StringIO('invalid json'))
    @patch('sys.stderr', new_callable=io.StringIO)
    @patch('sys.stdout', new_callable=io.StringIO)
    def test_run_operation_invalid_json_input(
        self, mock_stdout, mock_stderr, mock_runner_class
    ):
        """Test that invalid JSON input shows warning and uses empty dict."""
        # Setup mock runner
        mock_runner = MagicMock()
        mock_runner.run.return_value = {
            'operation_id': 'test-op',
            'status': 'success'
        }
        mock_runner_class.return_value = mock_runner

        # Create mock args
        args = MagicMock()
        args.operation_id = 'test-op'
        args.parent_operation = None
        args.dry_run = False
        args.verbose = False

        exit_code = run_operation(args)

        # Check warning was printed to stderr
        stderr_output = mock_stderr.getvalue()
        self.assertIn('Warning', stderr_output)
        self.assertIn('Invalid JSON', stderr_output)

        # Check empty dict was passed to runner
        call_args = mock_runner.run.call_args
        self.assertEqual(call_args.kwargs['input_data'], {})

    @patch('cli.OperationRunner')
    @patch('sys.stdin', io.StringIO('{"inputs": {"key": "value"}}'))
    @patch('sys.stdout', new_callable=io.StringIO)
    def test_run_operation_with_input_data(self, mock_stdout, mock_runner_class):
        """Test operation with valid JSON input."""
        # Setup mock runner
        mock_runner = MagicMock()
        mock_runner.run.return_value = {
            'operation_id': 'test-op',
            'status': 'success'
        }
        mock_runner_class.return_value = mock_runner

        # Create mock args
        args = MagicMock()
        args.operation_id = 'test-op'
        args.parent_operation = 'parent-123'
        args.dry_run = True
        args.verbose = True

        exit_code = run_operation(args)

        # Check input data was parsed correctly
        call_args = mock_runner.run.call_args
        self.assertEqual(call_args.kwargs['input_data'], {'inputs': {'key': 'value'}})
        self.assertEqual(call_args.kwargs['parent_operation'], 'parent-123')
        self.assertEqual(call_args.kwargs['dry_run'], True)

    @patch('cli.OperationRunner')
    @patch('sys.stdin', io.StringIO('{}'))
    @patch('sys.stdout', new_callable=io.StringIO)
    def test_run_operation_exit_codes(self, mock_stdout, mock_runner_class):
        """Test different exit codes based on result status."""
        mock_runner = MagicMock()
        mock_runner_class.return_value = mock_runner

        test_cases = [
            ('success', 0),
            ('approved', 0),
            ('changes_requested', 2),
            ('error', 1),
            ('unknown', 1),
        ]

        for status, expected_code in test_cases:
            mock_runner.run.return_value = {
                'operation_id': 'test-op',
                'status': status
            }

            args = MagicMock()
            args.operation_id = 'test-op'
            args.parent_operation = None
            args.dry_run = False
            args.verbose = False

            exit_code = run_operation(args)
            self.assertEqual(exit_code, expected_code, f"Status '{status}' should return {expected_code}")


if __name__ == '__main__':
    unittest.main()
