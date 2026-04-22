"""JSON schema validation."""

import json
import os
from typing import Any, Dict, Optional


class SchemaValidator:
    def __init__(self, acts_dir: str) -> None:
        self.acts_dir = acts_dir
        self.schemas: Dict[str, Dict[str, Any]] = {}
        self._load_schemas()

    def _load_schemas(self) -> None:
        """Load all JSON schemas from the schemas directory."""
        schemas_dir = os.path.join(self.acts_dir, 'schemas')
        if not os.path.isdir(schemas_dir):
            return

        for filename in os.listdir(schemas_dir):
            if filename.endswith('.json'):
                schema_path = os.path.join(schemas_dir, filename)
                try:
                    with open(schema_path, 'r') as f:
                        schema_name = filename[:-5]  # Remove .json extension
                        self.schemas[schema_name] = json.load(f)
                except (json.JSONDecodeError, IOError):
                    # Skip invalid schema files
                    pass

    def _get_schema_for_operation(
        self,
        operation_id: str,
        schema_type: str
    ) -> Optional[Dict[str, Any]]:
        """Get the schema for a specific operation and type (input/output)."""
        # First try operation-specific schema
        schema_key = f"{operation_id}-{schema_type}"
        if schema_key in self.schemas:
            return self.schemas[schema_key]

        # Fall back to default schema for type
        if schema_type in self.schemas:
            return self.schemas[schema_type]

        return None

    def _check_required_fields(
        self,
        data: Dict[str, Any],
        schema: Dict[str, Any]
    ) -> bool:
        """Check if all required fields are present in data."""
        required = schema.get('required', [])
        for field in required:
            if field not in data:
                return False
        return True

    def validate_input(self, operation_id: str, data: Dict[str, Any]) -> bool:
        """Validate operation input against schema."""
        schema = self._get_schema_for_operation(operation_id, 'input')
        if schema is None:
            # No schema defined, validation passes
            return True

        return self._check_required_fields(data, schema)

    def validate_output(self, operation_id: str, data: Dict[str, Any]) -> bool:
        """Validate operation output against schema."""
        schema = self._get_schema_for_operation(operation_id, 'output')
        if schema is None:
            # No schema defined, validation passes
            return True

        return self._check_required_fields(data, schema)
