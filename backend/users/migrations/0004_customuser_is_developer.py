# Generated manually for is_developer field

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0003_alter_customuser_credits_alter_customuser_inventory'),
    ]

    operations = [
        migrations.AddField(
            model_name='customuser',
            name='is_developer',
            field=models.BooleanField(default=False),
        ),
    ]
