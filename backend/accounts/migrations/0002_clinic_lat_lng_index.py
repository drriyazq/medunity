"""
Partial index on (lat, lng) for Haversine radius queries in the SOS module.
Only indexes rows where lat IS NOT NULL — saves space on records without GPS.
"""
from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0001_initial"),
    ]

    operations = [
        migrations.RunSQL(
            sql="""
            CREATE INDEX IF NOT EXISTS accounts_clinic_lat_lng_idx
            ON accounts_clinic (lat, lng)
            WHERE lat IS NOT NULL;
            """,
            reverse_sql="DROP INDEX IF EXISTS accounts_clinic_lat_lng_idx;",
        ),
    ]
