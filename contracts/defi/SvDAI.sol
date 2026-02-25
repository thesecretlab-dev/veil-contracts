// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
  function balanceOf(address account) external view returns (uint256);
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @notice Savings vDAI (svDAI).
/// @dev Minimal non-rebasing vault over vDAI:
/// - Deposit vDAI, receive svDAI shares.
/// - vDAI can be donated to the vault (protocol revenue) to increase assets/share.
contract SvDAI {
  string public constant name = "Savings vDAI";
  string public constant symbol = "svDAI";
  uint8 public constant decimals = 18;

  event Approval(address indexed owner, address indexed spender, uint256 value);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Deposit(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
  event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
  event Donation(address indexed caller, uint256 assets);

  IERC20 public immutable asset; // vDAI token (Maker Dai)

  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(address asset_) {
    require(asset_ != address(0), "SvDAI/invalid-asset");
    asset = IERC20(asset_);
  }

  function totalAssets() public view returns (uint256) {
    return asset.balanceOf(address(this));
  }

  function convertToShares(uint256 assets_) public view returns (uint256) {
    uint256 supply = totalSupply;
    if (supply == 0) return assets_;
    uint256 assetsBefore = totalAssets();
    if (assetsBefore == 0) return assets_;
    return (assets_ * supply) / assetsBefore;
  }

  function convertToAssets(uint256 shares_) public view returns (uint256) {
    uint256 supply = totalSupply;
    if (supply == 0) return shares_;
    uint256 assetsNow = totalAssets();
    return (shares_ * assetsNow) / supply;
  }

  function previewDeposit(uint256 assets_) external view returns (uint256) {
    return convertToShares(assets_);
  }

  function previewRedeem(uint256 shares_) external view returns (uint256) {
    return convertToAssets(shares_);
  }

  function approve(address spender, uint256 value) external returns (bool) {
    allowance[msg.sender][spender] = value;
    emit Approval(msg.sender, spender, value);
    return true;
  }

  function transfer(address to, uint256 value) external returns (bool) {
    return transferFrom(msg.sender, to, value);
  }

  function transferFrom(address from, address to, uint256 value) public returns (bool) {
    require(to != address(0), "SvDAI/invalid-recipient");

    if (from != msg.sender) {
      uint256 allowed = allowance[from][msg.sender];
      if (allowed != type(uint256).max) {
        require(allowed >= value, "SvDAI/insufficient-allowance");
        unchecked {
          allowance[from][msg.sender] = allowed - value;
        }
        emit Approval(from, msg.sender, allowance[from][msg.sender]);
      }
    }

    require(balanceOf[from] >= value, "SvDAI/insufficient-balance");
    unchecked {
      balanceOf[from] -= value;
      balanceOf[to] += value;
    }
    emit Transfer(from, to, value);
    return true;
  }

  function deposit(uint256 assets_, address receiver) external returns (uint256 shares) {
    require(receiver != address(0), "SvDAI/invalid-receiver");
    require(assets_ > 0, "SvDAI/zero-assets");

    uint256 supply = totalSupply;
    uint256 assetsBefore = totalAssets();

    require(asset.transferFrom(msg.sender, address(this), assets_), "SvDAI/transfer-in-failed");

    if (supply == 0 || assetsBefore == 0) {
      shares = assets_;
    } else {
      shares = (assets_ * supply) / assetsBefore;
    }
    require(shares > 0, "SvDAI/zero-shares");

    totalSupply = supply + shares;
    unchecked {
      balanceOf[receiver] += shares;
    }

    emit Deposit(msg.sender, receiver, assets_, shares);
    emit Transfer(address(0), receiver, shares);
  }

  function redeem(uint256 shares_, address receiver, address owner) external returns (uint256 assetsOut) {
    require(receiver != address(0), "SvDAI/invalid-receiver");
    require(owner != address(0), "SvDAI/invalid-owner");
    require(shares_ > 0, "SvDAI/zero-shares");

    if (owner != msg.sender) {
      uint256 allowed = allowance[owner][msg.sender];
      if (allowed != type(uint256).max) {
        require(allowed >= shares_, "SvDAI/insufficient-allowance");
        unchecked {
          allowance[owner][msg.sender] = allowed - shares_;
        }
        emit Approval(owner, msg.sender, allowance[owner][msg.sender]);
      }
    }

    uint256 supply = totalSupply;
    require(balanceOf[owner] >= shares_, "SvDAI/insufficient-balance");
    require(supply > 0, "SvDAI/empty");

    uint256 assetsNow = totalAssets();
    assetsOut = (shares_ * assetsNow) / supply;
    require(assetsOut > 0, "SvDAI/zero-assets");

    unchecked {
      balanceOf[owner] -= shares_;
    }
    totalSupply = supply - shares_;

    emit Withdraw(msg.sender, receiver, owner, assetsOut, shares_);
    emit Transfer(owner, address(0), shares_);

    require(asset.transfer(receiver, assetsOut), "SvDAI/transfer-out-failed");
  }

  function donate(uint256 assets_) external {
    require(assets_ > 0, "SvDAI/zero-assets");
    require(asset.transferFrom(msg.sender, address(this), assets_), "SvDAI/donate-failed");
    emit Donation(msg.sender, assets_);
  }
}

