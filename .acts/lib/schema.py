"""JSON schema validation."""

import json
import os

class SchemaValidator:
    def __init__(self, acts_dir):
        self.acts_dir = acts_dir
        self.schemas = {}
    
    def validate_input(self, operation_id, data):
        """Validate operation input against schema."""
        # TODO: Implement schema validation
        return True
    
    def validate_output(self, operation_id, data):
        """Validate operation output against schema."""
        # TODO: Implement schema validation
        return True
