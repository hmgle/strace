/* Return codes: 1 - ok, 0 - ignore, other - error. */
static int
arch_get_scno(struct tcb *tcp)
{
	tcp->scno = i386_regs.orig_eax;
	return 1;
}
