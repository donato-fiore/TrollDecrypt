#import "TDAlternateIconCell.h"

@implementation TDAlternateIconCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _iconImageView = [[UIImageView alloc] init];
        _iconNameLabel = [[UILabel alloc] init];

        _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconImageView.layer.masksToBounds = YES;
        _iconImageView.layer.cornerRadius = 15.0;

        _iconNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _iconNameLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];

        [self.contentView addSubview:_iconImageView];
        [self.contentView addSubview:_iconNameLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15.0],
            [_iconImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconImageView.widthAnchor constraintEqualToConstant:60],
            [_iconImageView.heightAnchor constraintEqualToConstant:60],

            [_iconNameLabel.leadingAnchor constraintEqualToAnchor:_iconImageView.trailingAnchor constant:15.0],
            [_iconNameLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconNameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15.0],
        ]];


    }
    return self;
}

@end