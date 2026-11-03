import { Body, Controller, Delete, Post, Req, UseGuards } from '@nestjs/common';
import { AuthService } from '../auth/auth.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { FilesService } from '../files/files.service';
import { DeleteAccountDto } from './delete-account.dto';

type AccountRequest = {
  user: { id: string; sessionId: string };
};

@Controller('auth')
@UseGuards(JwtAuthGuard)
export class AccountController {
  constructor(
    private readonly auth: AuthService,
    private readonly files: FilesService,
  ) {}

  @Post('logout')
  async logout(@Req() request: AccountRequest) {
    await this.auth.revokeDevice(
      request.user.id,
      request.user.sessionId,
    );
    return { signedOut: true };
  }

  @Delete('account')
  async deleteAccount(
    @Req() request: AccountRequest,
    @Body() dto: DeleteAccountDto,
  ) {
    await this.auth.verifyAccountPassword(request.user.id, dto.password);
    await this.auth.revokeAllDevices(request.user.id);
    await this.files.deleteAllForOwner(request.user.id);
    await this.auth.deleteAccountRecord(request.user.id);
    return { deleted: true };
  }
}
