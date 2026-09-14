import { ArgumentsHost, Catch, ExceptionFilter, HttpException, Logger } from '@nestjs/common';
import { Response } from 'express';

/**
 * Consolidated error handling. Without this, anything that isn't a Nest
 * HttpException (a plain Error thrown from a service, a Stellar SDK
 * network failure) falls through to Nest's default handler, which returns
 * a bare 500 with no useful body and logs nothing consistent server-side.
 * Two cases:
 *
 *  1. Nest HttpException (ValidationPipe errors, NotFoundException, the
 *     hard gate's ForbiddenException, etc.) — pass its status/body through
 *     unchanged, this filter adds nothing.
 *  2. Anything else — a generic 500 with no internal detail leaked to the
 *     client, but the full error logged server-side so it's not silently
 *     swallowed. Upstream failures (Horizon/Soroban RPC unreachable) read
 *     as 500s here; the app surfaces them as "network" errors.
 */
@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<Response>();

    if (exception instanceof HttpException) {
      res.status(exception.getStatus()).json(exception.getResponse());
      return;
    }

    this.logger.error('Unhandled exception', exception instanceof Error ? exception.stack : exception);
    res.status(500).json({
      statusCode: 500,
      error: 'Internal Server Error',
      message: 'Something went wrong. Try again, and if it keeps happening, contact support.',
    });
  }
}
