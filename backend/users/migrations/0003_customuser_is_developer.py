# Generated manually for is_developer field

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0002_rename_profilepicture_avatar_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='customuser',
            name='is_developer',
            field=models.BooleanField(default=False),
        ),
    ]
