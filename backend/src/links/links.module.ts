import { Module } from '@nestjs/common';
import { LinksService } from './links.service';
import { LinksController, LinkPreviewController } from './links.controller';
import { UsersModule } from '../users/users.module';

@Module({
  imports: [UsersModule],
  providers: [LinksService],
  controllers: [LinksController, LinkPreviewController],
  exports: [LinksService],
})
export class LinksModule {}
