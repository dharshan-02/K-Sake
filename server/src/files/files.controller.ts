import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { Request } from 'express';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreateFileDto, RenameFileDto } from './file.dto';
import { FilesService } from './files.service';

type AuthRequest = Request & { user: { id: string } };

@UseGuards(JwtAuthGuard)
@Controller('files')
export class FilesController {
  constructor(private readonly files: FilesService) {}
  @Get() list(@Req() req: AuthRequest) { return this.files.list(req.user.id); }
  @Post('upload') begin(@Req() req: AuthRequest, @Body() dto: CreateFileDto) { return this.files.beginUpload(req.user.id, dto); }
  @Post(':id/complete') complete(@Req() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string) { return this.files.finishUpload(req.user.id, id); }
  @Get(':id/download') download(@Req() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string) { return this.files.download(req.user.id, id); }
  @Patch(':id') rename(@Req() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: RenameFileDto) { return this.files.rename(req.user.id, id, dto.name, dto.expectedUpdatedAt); }
  @Delete(':id') remove(@Req() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string) { return this.files.remove(req.user.id, id); }
}
