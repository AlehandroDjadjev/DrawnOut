from django.core.management.base import BaseCommand, CommandError
from django.contrib.auth import get_user_model


class Command(BaseCommand):
    help = "Reset a user's password (dev helper)."

    def add_arguments(self, parser):
        parser.add_argument("username", type=str)
        parser.add_argument("new_password", type=str)
        parser.add_argument(
            "--activate",
            action="store_true",
            help="Also set user.is_active=True",
        )

    def handle(self, *args, **options):
        username: str = options["username"].strip()
        new_password: str = options["new_password"]
        activate: bool = bool(options.get("activate"))

        if not username:
            raise CommandError("username cannot be empty")
        if not new_password:
            raise CommandError("new_password cannot be empty")

        User = get_user_model()

        try:
            user = User.objects.get(username=username)
        except User.DoesNotExist as exc:
            raise CommandError(f"No user found with username: {username}") from exc

        user.set_password(new_password)
        if activate:
            user.is_active = True
        user.save(update_fields=["password", "is_active"] if activate else ["password"])

        self.stdout.write(self.style.SUCCESS(f"Password reset for '{username}'."))
