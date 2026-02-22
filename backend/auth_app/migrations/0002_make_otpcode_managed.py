# Migration to make OTPCode table managed by Django
# Previously it was managed=False (assumed to exist in Supabase),
# but this caused the table to not exist on production Render deployment.
# Now Django will create and manage this table via migrations.

import uuid
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('auth_app', '0001_initial'),
    ]

    operations = [
        # Step 1: Make Django start managing the table (create it if it doesn't exist)
        migrations.AlterModelOptions(
            name='otpcode',
            options={
                'db_table': 'otp_codes',
                'ordering': ['-created_at'],
            },
        ),
        migrations.SeparateDatabaseAndState(
            # Only update state - the table already exists on Supabase
            # OR Django will create it fresh when it doesn't exist (Render)
            database_operations=[
                # Create the table if it doesn't already exist
                # Using RunSQL with IF NOT EXISTS for safety
                migrations.RunSQL(
                    sql="""
                        CREATE TABLE IF NOT EXISTS otp_codes (
                            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                            phone VARCHAR(15) NOT NULL,
                            code VARCHAR(6) NOT NULL,
                            is_used BOOLEAN NOT NULL DEFAULT FALSE,
                            expires_at TIMESTAMPTZ NOT NULL,
                            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                        );
                        CREATE INDEX IF NOT EXISTS otp_codes_phone_is_used_idx 
                            ON otp_codes (phone, is_used);
                    """,
                    reverse_sql="DROP TABLE IF EXISTS otp_codes;",
                ),
            ],
            state_operations=[
                migrations.AlterField(
                    model_name='otpcode',
                    name='id',
                    field=models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False),
                ),
            ],
        ),
        # Step 2: Add the index at the Django ORM level
        migrations.AddIndex(
            model_name='otpcode',
            index=models.Index(fields=['phone', 'is_used'], name='otp_phone_is_used_idx'),
        ),
    ]
