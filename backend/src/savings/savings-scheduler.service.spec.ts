import { SavingsSchedulerService } from './savings-scheduler.service';
import { SavingsService } from './savings.service';

describe('SavingsSchedulerService', () => {
  it('delegates to SavingsService.runDueCheck', async () => {
    const runDueCheck = jest.fn().mockResolvedValue({ goalsChecked: 0, contributionsCreated: 0 });
    const savings = { runDueCheck } as unknown as SavingsService;

    await new SavingsSchedulerService(savings).handleDueCheck();

    expect(runDueCheck).toHaveBeenCalledTimes(1);
  });

  it('does not throw when a contribution is actually created (log-only branch)', async () => {
    const runDueCheck = jest.fn().mockResolvedValue({ goalsChecked: 3, contributionsCreated: 2 });
    const savings = { runDueCheck } as unknown as SavingsService;

    await expect(new SavingsSchedulerService(savings).handleDueCheck()).resolves.toBeUndefined();
  });
});
