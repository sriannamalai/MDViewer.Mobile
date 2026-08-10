/// Where a [VaultEntry]/[RecentEntry] comes from — distinguishes the
/// always-present bundled sample vault, a user-picked folder, and a single
/// file opened via the OS "Open with" flow.
///
/// `openedFile` is defined now (per the vault layer's data-model contract)
/// but its read path is wired up in the search/open-with task — see
/// `VaultState._providerFor`'s doc comment.
enum VaultSource { sample, folder, openedFile }
